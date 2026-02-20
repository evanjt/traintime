using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.Communications;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Math;

class TrainTimeView extends WatchUi.View {

    private var mLocationInfo;
    private var mTrainData;
    private var mTimer;
    private var mStatus;
    private var mStationId;
    private var mStationName;
    private var mRequestInFlight;
    private var mWalkInfo;
    private var mStations;
    private var mStationIndex;

    function initialize() {
        View.initialize();
        mLocationInfo = null;
        mTrainData = null;
        mStatus = "GPS: Searching...";
        mStationId = null;
        mStationName = null;
        mRequestInFlight = false;
        mWalkInfo = null;
        mStations = null;
        mStationIndex = 0;
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    function onShow() {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, new Lang.Method(self, :onPosition));

        // Poll immediately (may already have a cached position)
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            onPosition(info);
        }

        mTimer = new Timer.Timer();
        mTimer.start(new Lang.Method(self, :onTimerTick), 10000, true);
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, new Lang.Method(self, :onPosition));
    }

    // Calculate usable width at a given Y on a round display
    function getUsableWidth(y, width, height) {
        var r = width / 2;
        var dy = y - height / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) { return 0; }
        var hw = Math.sqrt(r * r - dy * dy).toNumber();
        return hw * 2;
    }

    function truncateToFit(dc, text, font, maxWidth) {
        var dims = dc.getTextDimensions(text, font);
        if (dims[0] <= maxWidth) {
            return text;
        }
        // Estimate chars that fit
        var charW = dims[0] / text.length();
        var maxChars = (maxWidth / charW).toNumber();
        if (maxChars < 2) { maxChars = 2; }
        if (maxChars >= text.length()) {
            return text;
        }
        return text.substring(0, maxChars - 1) + ".";
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        if (mStationName != null) {
            // Walking info line
            if (mWalkInfo != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                var walkY = height * 12 / 100;
                var walkMaxW = getUsableWidth(walkY + 8, width, height) - 10;
                var walkText = truncateToFit(dc, mWalkInfo, Graphics.FONT_XTINY, walkMaxW);
                dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                    walkText, Graphics.TEXT_JUSTIFY_CENTER);
            }

            // Station name
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var stationY = height * 22 / 100;
            var stationMaxW = getUsableWidth(stationY + 12, width, height) - 10;
            var stationText = mStationName.toUpper();
            var stationFont = Graphics.FONT_MEDIUM;
            var dims = dc.getTextDimensions(stationText, stationFont);
            if (dims[0] > stationMaxW) {
                stationFont = Graphics.FONT_SMALL;
                dims = dc.getTextDimensions(stationText, stationFont);
                if (dims[0] > stationMaxW) {
                    stationFont = Graphics.FONT_TINY;
                    stationText = truncateToFit(dc, stationText, stationFont, stationMaxW);
                }
            }
            dc.drawText(centerX, stationY, stationFont,
                stationText, Graphics.TEXT_JUSTIFY_CENTER);

            if (mTrainData != null && mTrainData.size() > 0) {
                // Separator arc
                dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                var arcY = height * 32 / 100;
                var arcR = width * 2;
                dc.drawArc(centerX, arcY + arcR, arcR,
                    Graphics.ARC_COUNTER_CLOCKWISE, 83, 97);

                // Train rows
                var maxTrains = 4;
                if (height < 240) {
                    maxTrains = 3;
                }
                var startY = height * 36 / 100;
                var rowSpacing = height * 14 / 100;

                var count = mTrainData.size();
                if (count > maxTrains) {
                    count = maxTrains;
                }
                for (var i = 0; i < count; i++) {
                    drawTrainRow(dc, mTrainData[i],
                        startY + i * rowSpacing, width, height);
                }
            } else if (mTrainData != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                    "No departures", Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                var bodyMsg = "Loading...";
                if (!mRequestInFlight) {
                    bodyMsg = mStatus;
                }
                dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                    bodyMsg, Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height / 2 - 20, Graphics.FONT_SMALL,
                mStatus, Graphics.TEXT_JUSTIFY_CENTER);

            if (mLocationInfo != null && mLocationInfo.position != null) {
                var coords = mLocationInfo.position.toDegrees();
                var coordText = coords[0].format("%.4f") + ", " + coords[1].format("%.4f");
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, height / 2 + 10, Graphics.FONT_XTINY,
                    coordText, Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    function drawTrainRow(dc, train, y, width, height) {
        var minutesUntil = train["min"];
        var delay = train["delay"];
        var platform = train["plat"];
        var platformChanged = train["platChg"];
        var destination = train["dest"];
        var isGone = (minutesUntil < 0);

        // Vertical alignment: FONT_TINY for minutes, FONT_XTINY for rest
        var tinyH = dc.getFontHeight(Graphics.FONT_TINY);
        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var xtinyY = y + (tinyH - xtinyH) / 2;

        // Fixed column X positions (absolute, so columns align across rows)
        var minRightX = width * 24 / 100;
        var delayX = width * 26 / 100;
        var platX = width * 38 / 100;
        var destX = width * 50 / 100;

        // Right edge for this row on round display (for destination truncation)
        var rowCenterY = y + tinyH / 2;
        var usable = getUsableWidth(rowCenterY, width, height);
        var rightEdge = (width + usable) / 2 - 4;

        // Minutes column (right-aligned, FONT_TINY)
        var minText;
        if (isGone) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            minText = "gone";
        } else if (minutesUntil == 0) {
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            minText = "now";
        } else if (minutesUntil <= 2) {
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            minText = minutesUntil + "'";
        } else {
            dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            minText = minutesUntil + "'";
        }
        dc.drawText(minRightX, y, Graphics.FONT_TINY,
            minText, Graphics.TEXT_JUSTIFY_RIGHT);

        // Delay column (FONT_XTINY, orange)
        if (delay > 0 && !isGone) {
            dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);
            dc.drawText(delayX, xtinyY, Graphics.FONT_XTINY,
                "+" + delay, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Platform column (FONT_XTINY)
        if (platform.length() > 0) {
            var platText = "P" + platform;
            if (isGone) {
                dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
                dc.drawText(platX, xtinyY, Graphics.FONT_XTINY,
                    platText, Graphics.TEXT_JUSTIFY_LEFT);
            } else if (platformChanged) {
                var platDims = dc.getTextDimensions(platText, Graphics.FONT_XTINY);
                var pad = 2;
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(platX - pad, xtinyY, platDims[0] + 2 * pad, platDims[1]);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(platX, xtinyY, Graphics.FONT_XTINY,
                    platText, Graphics.TEXT_JUSTIFY_LEFT);
            } else {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.drawText(platX, xtinyY, Graphics.FONT_XTINY,
                    platText, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }

        // Destination column (FONT_XTINY, truncated to fit round edge)
        if (isGone) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        var maxDestW = rightEdge - destX;
        var destText = truncateToFit(dc, destination, Graphics.FONT_XTINY, maxDestW);
        dc.drawText(destX, xtinyY, Graphics.FONT_XTINY,
            destText, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function nextStation() {
        if (mStations != null && mStations.size() > 1) {
            mStationIndex = (mStationIndex + 1) % mStations.size();
            selectStation(mStationIndex);
        }
    }

    function previousStation() {
        if (mStations != null && mStations.size() > 1) {
            mStationIndex = mStationIndex - 1;
            if (mStationIndex < 0) {
                mStationIndex = mStations.size() - 1;
            }
            selectStation(mStationIndex);
        }
    }

    function selectStation(index) {
        var station = mStations[index];
        mStationId = station["id"];
        mStationName = station.hasKey("label") ? station["label"] : "Station";
        var distance = station.hasKey("dist") ? station["dist"] : 0;
        mWalkInfo = formatWalkInfo(distance);
        mStatus = mStationName;
        mTrainData = null;
        mRequestInFlight = true;
        fetchStationboard(mStationId);
        WatchUi.requestUpdate();
    }

    function onPosition(info) {
        mLocationInfo = info;

        if (info == null || info.position == null) {
            mStatus = "GPS: Searching...";
            WatchUi.requestUpdate();
            return;
        }

        var coords = info.position.toDegrees();
        var lat = coords[0];
        var lon = coords[1];

        // Switzerland bounding box check
        if (lat < 45.8 || lat > 47.8 || lon < 5.9 || lon > 10.5) {
            mStationName = null;
            mStationId = null;
            mStations = null;
            mTrainData = null;
            mWalkInfo = null;
            mStatus = "Not in Switzerland";
            WatchUi.requestUpdate();
            return;
        }

        if (mStationId == null && !mRequestInFlight) {
            mStatus = "Finding stations...";
            mRequestInFlight = true;
            fetchTrainData(lat, lon);
        }
        WatchUi.requestUpdate();
    }

    function onTimerTick() {
        // Always poll for updated position (detects leaving Switzerland)
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            mLocationInfo = info;
            var coords = info.position.toDegrees();
            var lat = coords[0];
            var lon = coords[1];

            if (lat < 45.8 || lat > 47.8 || lon < 5.9 || lon > 10.5) {
                mStationName = null;
                mStationId = null;
                mStations = null;
                mTrainData = null;
                mWalkInfo = null;
                mStatus = "Not in Switzerland";
                WatchUi.requestUpdate();
                return;
            }
        }

        if (mRequestInFlight) {
            return;
        }

        if (mStationId != null) {
            mRequestInFlight = true;
            fetchStationboard(mStationId);
        } else if (mLocationInfo != null && mLocationInfo.position != null) {
            mRequestInFlight = true;
            var coords = mLocationInfo.position.toDegrees();
            fetchTrainData(coords[0], coords[1]);
        }
    }

    function fetchTrainData(lat, lon) {
        var url = "https://search.ch/timetable/api/completion.en.json"
            + "?latlon=" + lat + "," + lon
            + "&accuracy=10000&show_ids=1";

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {}
        };

        Communications.makeWebRequest(url, null, params, new Lang.Method(self, :onStationsReceived));
    }

    function onStationsReceived(responseCode, data) {
        mRequestInFlight = false;

        if (responseCode == 200 && data != null) {
            var stations = null;
            if (data instanceof Lang.Array) {
                stations = data;
            }

            if (stations != null && stations.size() > 0) {
                mStations = [];
                var limit = stations.size();
                if (limit > 5) {
                    limit = 5;
                }
                for (var i = 0; i < limit; i++) {
                    var s = stations[i];
                    if (s.hasKey("id") && s["id"] != null) {
                        mStations.add(s);
                    }
                }

                if (mStations.size() > 0) {
                    mStationIndex = 0;
                    var station = mStations[0];
                    mStationId = station["id"];
                    mStationName = station.hasKey("label") ? station["label"] : "Station";
                    var distance = station.hasKey("dist") ? station["dist"] : 0;
                    mWalkInfo = formatWalkInfo(distance);
                    mStatus = mStationName;
                    WatchUi.requestUpdate();

                    mRequestInFlight = true;
                    fetchStationboard(mStationId);
                    return;
                }
            }

            mStatus = "No stations nearby";
            mTrainData = null;
        } else if (responseCode == 429) {
            mStatus = "Rate limited";
        } else {
            mStatus = "Station error: " + responseCode;
            mTrainData = null;
        }
        WatchUi.requestUpdate();
    }

    function fetchStationboard(stationId) {
        var url = "https://transport.opendata.ch/v1/stationboard"
            + "?id=" + stationId
            + "&limit=5"
            + "&fields[]=stationboard/to"
            + "&fields[]=stationboard/category"
            + "&fields[]=stationboard/stop/departureTimestamp"
            + "&fields[]=stationboard/stop/delay"
            + "&fields[]=stationboard/stop/platform"
            + "&fields[]=stationboard/stop/prognosis/platform";

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {}
        };

        Communications.makeWebRequest(url, null, params, new Lang.Method(self, :onTrainDataReceived));
    }

    function onTrainDataReceived(responseCode, data) {
        mRequestInFlight = false;

        if (responseCode == 200 && data != null && data.hasKey("stationboard")) {
            mTrainData = [];
            var departures = data["stationboard"];
            var nowSeconds = Time.now().value();

            for (var i = 0; i < departures.size() && i < 5; i++) {
                var departure = departures[i];
                var destination = departure.hasKey("to") ? departure["to"] : "?";
                // Platform: prefer prognosis (changed platform) over scheduled
                var platform = "";
                var platformChanged = false;
                if (departure.hasKey("stop")) {
                    var stop = departure["stop"];
                    var progPlatform = null;
                    if (stop.hasKey("prognosis") && stop["prognosis"] != null
                        && stop["prognosis"].hasKey("platform")) {
                        progPlatform = stop["prognosis"]["platform"];
                    }
                    var schedPlatform = stop.hasKey("platform") ? stop["platform"] : null;

                    if (progPlatform != null) {
                        platform = progPlatform.toString();
                        if (schedPlatform != null && !schedPlatform.toString().equals(platform)) {
                            platformChanged = true;
                        }
                    } else if (schedPlatform != null) {
                        platform = schedPlatform.toString();
                    }
                }

                // Minutes until departure
                var minutesUntil = -1;
                if (departure.hasKey("stop") && departure["stop"].hasKey("departureTimestamp")) {
                    var depTs = departure["stop"]["departureTimestamp"];
                    if (depTs != null) {
                        minutesUntil = (depTs - nowSeconds) / 60;
                    }
                }

                // Delay
                var delay = 0;
                if (departure.hasKey("stop") && departure["stop"].hasKey("delay")) {
                    var rawDelay = departure["stop"]["delay"];
                    if (rawDelay != null && rawDelay > 0) {
                        delay = rawDelay;
                    }
                }

                mTrainData.add({
                    "min" => minutesUntil,
                    "delay" => delay,
                    "plat" => platform,
                    "platChg" => platformChanged,
                    "dest" => destination
                });
            }

            if (mStationName != null) {
                mStatus = mStationName;
            }
        } else {
            if (responseCode == 429) {
                mStatus = "Rate limited";
            } else {
                mStatus = "Error: " + responseCode;
            }
            mTrainData = null;
        }
        WatchUi.requestUpdate();
    }

    function formatWalkInfo(distanceMeters) {
        var dist = distanceMeters.toNumber();
        var walkMinutes = dist / 83;
        var timeStr;
        if (walkMinutes < 1) {
            timeStr = "<1 min";
        } else {
            timeStr = walkMinutes + " min";
        }

        var info = timeStr + " walk - " + dist + "m";

        if (mStations != null && mStations.size() > 1) {
            info = info + "  " + (mStationIndex + 1) + "/" + mStations.size();
        }

        return info;
    }
}
