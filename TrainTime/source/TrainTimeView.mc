using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.Communications;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Math;
using Toybox.Activity;
using Toybox.Application;
using Toybox.Weather;

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
    private var mCachedLat;
    private var mCachedLon;
    private var mCachedTime;
    private var mUsingCachedPosition;

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
        mUsingCachedPosition = false;
        mCachedLat = Application.Storage.getValue("lastLat");
        mCachedLon = Application.Storage.getValue("lastLon");
        mCachedTime = Application.Storage.getValue("lastTime");
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    function onShow() {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, new Lang.Method(self, :onPosition));

        // Poll immediately (getBestPosition handles fallbacks internally)
        var info = Position.getInfo();
        onPosition(info);

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
            // Walking info line / staleness indicator
            var walkY = height * 12 / 100;
            var walkMaxW = getUsableWidth(walkY + 8, width, height) - 10;
            if (mUsingCachedPosition) {
                var stalenessText = formatStalenessInfo();
                var delta = 0;
                if (mCachedTime != null) {
                    delta = Time.now().value() - mCachedTime;
                    if (delta < 0) { delta = 0; }
                }
                var color;
                if (delta <= 3600) {
                    color = 0xFFFF00;
                } else {
                    color = 0xFF5500;
                }
                var walkText = truncateToFit(dc, stalenessText, Graphics.FONT_XTINY, walkMaxW - 16);
                var textDims = dc.getTextDimensions(walkText, Graphics.FONT_XTINY);
                var textStartX = centerX - textDims[0] / 2;
                var iconX = textStartX - 10;
                var iconY = walkY + textDims[1] / 2;
                drawSatelliteIcon(dc, iconX, iconY, 5, color);
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                    walkText, Graphics.TEXT_JUSTIFY_CENTER);
            } else if (mWalkInfo != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
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
            // GPS status screen
            var gpsInfo = Position.getInfo();
            var qualityText = "No signal";
            var qualityColor = 0xFF5500;
            if (gpsInfo != null) {
                if (gpsInfo.accuracy == Position.QUALITY_GOOD) {
                    qualityText = "Signal: Good";
                    qualityColor = 0x00FF00;
                } else if (gpsInfo.accuracy == Position.QUALITY_USABLE) {
                    qualityText = "Signal: Usable";
                    qualityColor = 0x00FF00;
                } else if (gpsInfo.accuracy == Position.QUALITY_POOR) {
                    qualityText = "Signal: Poor";
                    qualityColor = 0xFFFF00;
                } else if (gpsInfo.accuracy == Position.QUALITY_LAST_KNOWN) {
                    qualityText = "Last known";
                    qualityColor = 0xFFFF00;
                }
            }

            // Satellite icon
            drawSatelliteIcon(dc, centerX, height / 2 - 45, 10, qualityColor);

            // Status text
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height / 2 - 25, Graphics.FONT_SMALL,
                mStatus, Graphics.TEXT_JUSTIFY_CENTER);

            // Quality text
            dc.setColor(qualityColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height / 2 + 5, Graphics.FONT_XTINY,
                qualityText, Graphics.TEXT_JUSTIFY_CENTER);

            // Show known coordinates if available
            if (mCachedLat != null && mCachedLon != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, height / 2 + 22, Graphics.FONT_XTINY,
                    mCachedLat.format("%.4f") + ", " + mCachedLon.format("%.4f"),
                    Graphics.TEXT_JUSTIFY_CENTER);
            } else if (mLocationInfo != null && mLocationInfo.position != null) {
                var coords = mLocationInfo.position.toDegrees();
                var coordText = coords[0].format("%.4f") + ", " + coords[1].format("%.4f");
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, height / 2 + 22, Graphics.FONT_XTINY,
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
        var best = getBestPosition();

        if (best == null) {
            mStatus = "GPS: Searching...";
            mUsingCachedPosition = false;
            WatchUi.requestUpdate();
            return;
        }

        var lat = best[0];
        var lon = best[1];
        var isLive = best[2];
        mUsingCachedPosition = !isLive;

        // Update debug display with valid live position
        if (isLive && info != null) {
            mLocationInfo = info;
        }

        if (!isInSwitzerland(lat, lon)) {
            if (isLive) {
                // Only clear stations on valid live GPS outside CH
                mStationName = null;
                mStationId = null;
                mStations = null;
                mTrainData = null;
                mWalkInfo = null;
                mStatus = "Not in Switzerland";
            }
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
        var best = getBestPosition();

        if (best != null) {
            var lat = best[0];
            var lon = best[1];
            var isLive = best[2];
            mUsingCachedPosition = !isLive;

            if (!isInSwitzerland(lat, lon)) {
                if (isLive) {
                    mStationName = null;
                    mStationId = null;
                    mStations = null;
                    mTrainData = null;
                    mWalkInfo = null;
                    mStatus = "Not in Switzerland";
                    WatchUi.requestUpdate();
                }
                return;
            }

            // Update debug display with valid live position
            if (isLive) {
                var info = Position.getInfo();
                if (info != null) {
                    mLocationInfo = info;
                }
            }

            // Re-enable GPS if using cached position (safety measure)
            if (!isLive) {
                Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, new Lang.Method(self, :onPosition));
                WatchUi.requestUpdate();
            }
        }

        if (mRequestInFlight) {
            return;
        }

        if (mStationId != null) {
            mRequestInFlight = true;
            fetchStationboard(mStationId);
        } else if (best != null) {
            mRequestInFlight = true;
            fetchTrainData(best[0], best[1]);
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

    function drawSatelliteIcon(dc, x, y, size, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        // Base dot (satellite)
        dc.fillCircle(x, y, size / 4);
        // Signal arcs
        dc.setPenWidth(2);
        dc.drawArc(x, y, size / 2, Graphics.ARC_COUNTER_CLOCKWISE, 30, 150);
        dc.drawArc(x, y, size, Graphics.ARC_COUNTER_CLOCKWISE, 35, 145);
        dc.setPenWidth(1);
    }

    function isPositionValid(info) {
        if (info == null || info.position == null) {
            return false;
        }
        if (info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return false;
        }
        var coords = info.position.toDegrees();
        var lat = coords[0];
        var lon = coords[1];
        if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
            return false;
        }
        if (lat == 0.0 && lon == 0.0) {
            return false;
        }
        return true;
    }

    function isInSwitzerland(lat, lon) {
        return (lat >= 45.8 && lat <= 47.8 && lon >= 5.9 && lon <= 10.5);
    }

    function saveCachedPosition(lat, lon, isLiveFix) {
        mCachedLat = lat;
        mCachedLon = lon;
        Application.Storage.setValue("lastLat", mCachedLat);
        Application.Storage.setValue("lastLon", mCachedLon);
        if (isLiveFix) {
            mCachedTime = Time.now().value();
            Application.Storage.setValue("lastTime", mCachedTime);
        }
    }

    function getActivityLocation() {
        try {
            var actInfo = Activity.getActivityInfo();
            if (actInfo != null && actInfo.currentLocation != null) {
                var coords = actInfo.currentLocation.toDegrees();
                var lat = coords[0];
                var lon = coords[1];
                if (lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0
                    && !(lat == 0.0 && lon == 0.0)) {
                    return [lat, lon];
                }
            }
        } catch (e) {
            // Activity API may not be available in all contexts
        }
        return null;
    }

    function getBestPosition() {
        // Tier 1: GPS position (live or last-known)
        var info = Position.getInfo();
        if (isPositionValid(info)) {
            var coords = info.position.toDegrees();
            var lat = coords[0];
            var lon = coords[1];
            // QUALITY_LAST_KNOWN is usable but not a fresh fix
            var isLive = (info.accuracy >= Position.QUALITY_POOR);
            if (isInSwitzerland(lat, lon)) {
                saveCachedPosition(lat, lon, isLive);
            }
            return [lat, lon, isLive];
        }

        // Tier 2: Activity location
        var actLoc = getActivityLocation();
        if (actLoc != null) {
            if (isInSwitzerland(actLoc[0], actLoc[1])) {
                saveCachedPosition(actLoc[0], actLoc[1], false);
            }
            return [actLoc[0], actLoc[1], false];
        }

        // Tier 3: Weather observation location (~1km accuracy)
        try {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null && conditions.observationLocationPosition != null) {
                var wCoords = conditions.observationLocationPosition.toDegrees();
                var wLat = wCoords[0];
                var wLon = wCoords[1];
                if (wLat >= -90.0 && wLat <= 90.0 && wLon >= -180.0 && wLon <= 180.0
                    && !(wLat == 0.0 && wLon == 0.0)) {
                    if (isInSwitzerland(wLat, wLon)) {
                        saveCachedPosition(wLat, wLon, false);
                    }
                    return [wLat, wLon, false];
                }
            }
        } catch (e) {
            // Weather API may crash on some devices
        }

        // Tier 4: Persistent cache
        if (mCachedLat != null && mCachedLon != null) {
            return [mCachedLat, mCachedLon, false];
        }

        return null;
    }

    function formatStalenessInfo() {
        var text = "GPS: cached";
        if (mCachedTime != null) {
            var delta = Time.now().value() - mCachedTime;
            if (delta < 0) { delta = 0; }
            var minutes = delta / 60;
            var hours = delta / 3600;
            var days = delta / 86400;
            if (days >= 1) {
                text = days + "d ago";
            } else if (hours >= 1) {
                text = hours + "h ago";
            } else {
                text = minutes + "m ago";
            }
        }
        if (mStations != null && mStations.size() > 1) {
            text = text + "  " + (mStationIndex + 1) + "/" + mStations.size();
        }
        return text;
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
