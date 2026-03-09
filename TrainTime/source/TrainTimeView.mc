using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.Communications;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Math;
using Toybox.Application.Storage;

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
    private var mLastSearchLat;
    private var mLastSearchLon;
    private var mRequestStartTime;
    private var mTrainStations;
    private var mBusStations;
    private var mTramStations;
    private var mCurrentMode;
    private var mAvailableModes;
    private var mGpsQuality;
    private var mLoadedFromCache;
    private var mStationLat;
    private var mStationLon;
    private var mTickCount;

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
        mLastSearchLat = null;
        mLastSearchLon = null;
        mRequestStartTime = null;
        mTrainStations = null;
        mBusStations = null;
        mTramStations = null;
        mCurrentMode = 0;
        mAvailableModes = [];
        mGpsQuality = Position.QUALITY_NOT_AVAILABLE;
        mLoadedFromCache = false;
        mStationLat = null;
        mStationLon = null;
        mTickCount = 0;
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    function onShow() {
        // Check for cached last-known position BEFORE enabling continuous GPS,
        // because enableLocationEvents can reset the cached position state.
        var info = Position.getInfo();

        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, new Lang.Method(self, :onPosition));

        if (info != null && info.position != null) {
            onPosition(info);
        }

        // If OS cache failed, try our own persistent storage
        if (mStationId == null && !mRequestInFlight) {
            var savedLat = Storage.getValue("lastLat");
            var savedLon = Storage.getValue("lastLon");
            if (savedLat != null && savedLon != null) {
                mLastSearchLat = savedLat;
                mLastSearchLon = savedLon;
                mLoadedFromCache = true;
                mGpsQuality = Position.QUALITY_LAST_KNOWN;
                mStatus = "Finding stations...";
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                fetchTrainData(savedLat, savedLon);
            }
        }

        mTimer = new Timer.Timer();
        mTimer.start(new Lang.Method(self, :onTimerTick), 5000, true);
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, new Lang.Method(self, :onPosition));
    }

    function hasMovedSignificantly(lat, lon) {
        if (mLastSearchLat == null || mLastSearchLon == null) {
            return true;
        }
        var dLat = lat - mLastSearchLat;
        if (dLat < 0) { dLat = -dLat; }
        var dLon = lon - mLastSearchLon;
        if (dLon < 0) { dLon = -dLon; }
        return (dLat > 0.0045 || dLon > 0.006);
    }

    function clearStationState() {
        mStationId = null;
        mStationName = null;
        mStations = null;
        mTrainStations = null;
        mBusStations = null;
        mTramStations = null;
        mTrainData = null;
        mWalkInfo = null;
        mStationIndex = 0;
        mAvailableModes = [];
        mStationLat = null;
        mStationLon = null;
    }

    function getStationsForMode(mode) {
        if (mode == 0) { return mTrainStations; }
        if (mode == 1) { return mBusStations; }
        if (mode == 2) { return mTramStations; }
        return null;
    }

    function cycleMode() {
        if (mAvailableModes.size() <= 1) {
            return;
        }
        var idx = 0;
        for (var i = 0; i < mAvailableModes.size(); i++) {
            if (mAvailableModes[i] == mCurrentMode) {
                idx = i;
                break;
            }
        }
        idx = (idx + 1) % mAvailableModes.size();
        mCurrentMode = mAvailableModes[idx];
        mStations = getStationsForMode(mCurrentMode);
        if (mStations != null && mStations.size() > 0) {
            mStationIndex = 0;
            selectStation(0);
        }
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

    function calculateDistance(lat1, lon1, lat2, lon2) {
        var dLat = (lat2 - lat1) * 111000;
        var dLon = (lon2 - lon1) * 75700; // ~111000 * cos(47°)
        return Math.sqrt(dLat * dLat + dLon * dLon).toNumber();
    }

    function updateWalkDistance() {
        if (mStationLat == null || mStationLon == null) {
            return;
        }
        if (mLocationInfo == null || mLocationInfo.position == null) {
            return;
        }
        var coords = mLocationInfo.position.toDegrees();
        var dist = calculateDistance(coords[0], coords[1], mStationLat, mStationLon);
        mWalkInfo = formatWalkInfo(dist);
    }

    function drawModeIndicators(dc, width, height) {
        if (mAvailableModes.size() == 0) {
            return;
        }

        var cy = height * 7 / 100;
        var iconSpacing = 24;
        var totalWidth = (mAvailableModes.size() - 1) * iconSpacing;
        var startX = width / 2 - totalWidth / 2;

        for (var i = 0; i < mAvailableModes.size(); i++) {
            var mode = mAvailableModes[i];
            var cx = startX + i * iconSpacing;
            var isActive = (mode == mCurrentMode);

            if (isActive) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            }

            if (mode == 0) {
                // Train: rectangle body + peaked roof + 2 wheels
                dc.fillRectangle(cx - 3, cy - 1, 6, 6);
                dc.fillPolygon([[cx - 3, cy - 1], [cx, cy - 4], [cx + 3, cy - 1]]);
                dc.fillCircle(cx - 2, cy + 6, 1);
                dc.fillCircle(cx + 2, cy + 6, 1);
            } else if (mode == 1) {
                // Bus: wider rectangle body + 2 wheels
                dc.fillRectangle(cx - 4, cy, 8, 5);
                dc.fillCircle(cx - 3, cy + 6, 1);
                dc.fillCircle(cx + 3, cy + 6, 1);
            } else {
                // Tram: rectangle body + pantograph + 2 wheels
                dc.fillRectangle(cx - 3, cy - 1, 6, 6);
                dc.setPenWidth(1);
                dc.drawLine(cx, cy - 1, cx, cy - 5);
                dc.drawLine(cx - 2, cy - 5, cx + 2, cy - 5);
                dc.fillCircle(cx - 2, cy + 6, 1);
                dc.fillCircle(cx + 2, cy + 6, 1);
            }

            // Active mode ring (only when multiple modes available)
            if (isActive && mAvailableModes.size() > 1) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawCircle(cx, cy + 1, 9);
            }
        }
    }

    function drawGpsIndicator(dc, width, height) {
        var cx = width - 18;
        var cy = 18;
        var r = 4;
        var color;
        if (mLoadedFromCache || mGpsQuality == Position.QUALITY_LAST_KNOWN) {
            color = 0x888888; // gray
        } else if (mGpsQuality == Position.QUALITY_NOT_AVAILABLE) {
            color = 0xFF0000; // red
        } else if (mGpsQuality == Position.QUALITY_POOR) {
            color = 0xFFAA00; // yellow
        } else {
            color = 0x00FF00; // green (USABLE or GOOD)
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // GPS quality indicator
        drawGpsIndicator(dc, width, height);

        if (mStationName != null) {
            // Mode indicators (above walk info)
            drawModeIndicators(dc, width, height);

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
        mStationLat = station.hasKey("lat") ? station["lat"] : null;
        mStationLon = station.hasKey("lon") ? station["lon"] : null;
        var distance = station.hasKey("dist") ? station["dist"] : 0;
        mWalkInfo = formatWalkInfo(distance);
        mStatus = mStationName;
        mTrainData = null;
        mRequestInFlight = true;
        mRequestStartTime = Time.now().value();
        fetchStationboard(mStationId);
        WatchUi.requestUpdate();
    }

    function onPosition(info) {
        // QUALITY_NOT_AVAILABLE means coordinates are garbage
        // (Fenix 6 bug: returns 0,0 instead of null)
        // QUALITY_LAST_KNOWN and above are valid (cached or live)
        if (info == null || info.position == null
                || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            if (mStationId == null && !mLoadedFromCache) {
                mStatus = "GPS: Searching...";
                WatchUi.requestUpdate();
            }
            return;
        }

        mGpsQuality = info.accuracy;

        var coords = info.position.toDegrees();
        var lat = coords[0];
        var lon = coords[1];

        // Belt-and-suspenders: reject obviously invalid coordinates
        if (lat > 90.0 || lat < -90.0 || lon > 180.0 || lon < -180.0) {
            return;
        }

        // Valid position (LAST_KNOWN or better) — store it
        mLocationInfo = info;

        // Persist location to Storage for next app launch
        Storage.setValue("lastLat", lat.toFloat());
        Storage.setValue("lastLon", lon.toFloat());

        // Switzerland bounding box check
        if (lat < 45.8 || lat > 47.8 || lon < 5.9 || lon > 10.5) {
            clearStationState();
            mStatus = "Not in Switzerland";
            WatchUi.requestUpdate();
            return;
        }

        // If we loaded from stale cache and now have a live GPS fix, re-search
        if (mLoadedFromCache && info.accuracy >= Position.QUALITY_POOR) {
            mLoadedFromCache = false;
            if (hasMovedSignificantly(lat, lon)) {
                clearStationState();
            }
            if (!mRequestInFlight) {
                mStatus = "Updating stations...";
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                fetchTrainData(lat, lon);
            }
            WatchUi.requestUpdate();
            return;
        }

        // Re-search stations if moved >500m from last search
        if (hasMovedSignificantly(lat, lon)) {
            clearStationState();
        }

        if (mStationId == null && !mRequestInFlight) {
            mStatus = "Finding stations...";
            mRequestInFlight = true;
            mRequestStartTime = Time.now().value();
            fetchTrainData(lat, lon);
        }

        // Update walk distance with live GPS
        updateWalkDistance();

        WatchUi.requestUpdate();
    }

    function onTimerTick() {
        mTickCount = mTickCount + 1;

        // Request timeout: if in-flight for >30s, force-reset
        if (mRequestInFlight && mRequestStartTime != null) {
            var elapsed = Time.now().value() - mRequestStartTime;
            if (elapsed > 30) {
                mRequestInFlight = false;
                mRequestStartTime = null;
            }
        }

        // Always poll for updated position (detects leaving Switzerland)
        // Only trust QUALITY_LAST_KNOWN or better — NOT_AVAILABLE gives garbage (0,0 or 180,180)
        var info = Position.getInfo();
        if (info != null && info.position != null
                && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            mGpsQuality = info.accuracy;
            var coords = info.position.toDegrees();
            var lat = coords[0];
            var lon = coords[1];

            // Belt-and-suspenders: only use valid coordinates
            if (lat <= 90.0 && lat >= -90.0 && lon <= 180.0 && lon >= -180.0) {
                mLocationInfo = info;

                if (lat < 45.8 || lat > 47.8 || lon < 5.9 || lon > 10.5) {
                    clearStationState();
                    mStatus = "Not in Switzerland";
                    WatchUi.requestUpdate();
                    return;
                }

                // Re-search stations if moved >500m from last search
                if (hasMovedSignificantly(lat, lon)) {
                    clearStationState();
                }
            }
        }

        // Update walk distance every tick (5s)
        updateWalkDistance();

        if (mRequestInFlight) {
            WatchUi.requestUpdate();
            return;
        }

        // Fetch stationboard only on even ticks (every 10s)
        if (mTickCount % 2 == 0) {
            if (mStationId != null) {
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                fetchStationboard(mStationId);
            } else if (mLocationInfo != null && mLocationInfo.position != null) {
                mStatus = "Finding stations...";
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                var coords = mLocationInfo.position.toDegrees();
                fetchTrainData(coords[0], coords[1]);
            }
        }

        WatchUi.requestUpdate();
    }

    function fetchTrainData(lat, lon) {
        mLastSearchLat = lat;
        mLastSearchLon = lon;

        var url = "https://transport.opendata.ch/v1/locations"
            + "?x=" + lat + "&y=" + lon
            + "&type=station";

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {}
        };

        Communications.makeWebRequest(url, null, params, new Lang.Method(self, :onStationsReceived));
    }

    function onStationsReceived(responseCode, data) {
        mRequestInFlight = false;
        mRequestStartTime = null;

        if (responseCode == 200 && data != null && data.hasKey("stations")) {
            var stations = data["stations"];

            if (stations != null && stations.size() > 0) {
                mTrainStations = [];
                mBusStations = [];
                mTramStations = [];

                for (var i = 0; i < stations.size(); i++) {
                    var s = stations[i];
                    if (!s.hasKey("id") || s["id"] == null) {
                        continue;
                    }
                    // Extract station coordinates
                    var sLat = null;
                    var sLon = null;
                    if (s.hasKey("coordinate") && s["coordinate"] != null) {
                        var coord = s["coordinate"];
                        if (coord.hasKey("x")) { sLat = coord["x"]; }
                        if (coord.hasKey("y")) { sLon = coord["y"]; }
                    }
                    // Normalize to common format used by selectStation()
                    var entry = {
                        "id" => s["id"],
                        "label" => s.hasKey("name") ? s["name"] : "Station",
                        "dist" => s.hasKey("distance") ? s["distance"] : 0,
                        "lat" => sLat,
                        "lon" => sLon
                    };
                    var icon = "";
                    if (s.hasKey("icon") && s["icon"] != null) {
                        icon = s["icon"].toString();
                    }
                    if (icon.equals("bus")) {
                        if (mBusStations.size() < 5) {
                            mBusStations.add(entry);
                        }
                    } else if (icon.equals("tram")) {
                        if (mTramStations.size() < 5) {
                            mTramStations.add(entry);
                        }
                    } else {
                        // Default: treat null/empty/unknown icons as train
                        // The API consistently labels bus/tram stops; null icons are railway stations
                        if (mTrainStations.size() < 5) {
                            mTrainStations.add(entry);
                        }
                    }
                }

                // Build available modes from non-empty categories
                mAvailableModes = [];
                if (mTrainStations.size() > 0) { mAvailableModes.add(0); }
                if (mBusStations.size() > 0) { mAvailableModes.add(1); }
                if (mTramStations.size() > 0) { mAvailableModes.add(2); }

                // If current mode has no stations, switch to first available
                var currentStations = getStationsForMode(mCurrentMode);
                if (currentStations == null || currentStations.size() == 0) {
                    if (mAvailableModes.size() > 0) {
                        mCurrentMode = mAvailableModes[0];
                    }
                }

                mStations = getStationsForMode(mCurrentMode);

                if (mStations != null && mStations.size() > 0) {
                    mStationIndex = 0;
                    var station = mStations[0];
                    mStationId = station["id"];
                    mStationName = station.hasKey("label") ? station["label"] : "Station";
                    mStationLat = station.hasKey("lat") ? station["lat"] : null;
                    mStationLon = station.hasKey("lon") ? station["lon"] : null;
                    var distance = station.hasKey("dist") ? station["dist"] : 0;
                    mWalkInfo = formatWalkInfo(distance);
                    mStatus = mStationName;
                    WatchUi.requestUpdate();

                    mRequestInFlight = true;
                    mRequestStartTime = Time.now().value();
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
        mRequestStartTime = null;

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
