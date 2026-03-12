using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.Communications;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Math;
using Toybox.Application.Storage;
using Toybox.Attention;

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
    private var mLastWalkDist;  // last known walk distance in meters
    // 0 = station view, 1 = train selection, 2 = focused tracking
    private var mAppState;
    private var mCursorIndex;
    private var mFocusedTrain;
    private var mHeading;  // GPS heading in radians, null when stationary
    private var mLastFetchTime;
    private var mConsecutiveErrors;
    private var mLastVibeTick;
    private var mMaxVisibleTrains;
    private var mMapActive;  // true when MapTrackView is pushed

    function initialize() {
        View.initialize();
        mLocationInfo = null;
        mTrainData = null;
        mStatus = "Loading...";
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
        mLastWalkDist = null;
        mAppState = 0;
        mCursorIndex = 0;
        mFocusedTrain = null;
        mHeading = null;
        mLastFetchTime = 0;
        mConsecutiveErrors = 0;
        mLastVibeTick = 0;
        mMaxVisibleTrains = 4;
        mMapActive = false;
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    function onShow() {
        // Check for cached last-known position BEFORE enabling continuous GPS,
        // because enableLocationEvents can reset the cached position state.
        var info = Position.getInfo();

        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));

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
        mTimer.start(method(:onTimerTick), 5000, true);
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
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
        if (mMapActive) {
            mMapActive = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
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
        mLastWalkDist = null;
        mAppState = 0;
        mCursorIndex = 0;
        mFocusedTrain = null;
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

    // --- State management ---

    function getAppState() {
        return mAppState;
    }

    function enterTrainSelection() {
        if (mTrainData == null || mTrainData.size() == 0) {
            return;
        }
        mAppState = 1;
        mCursorIndex = 0;
        var limit = mTrainData.size();
        if (limit > mMaxVisibleTrains) { limit = mMaxVisibleTrains; }
        for (var i = 0; i < limit; i++) {
            if (mTrainData[i]["min"] >= 0) {
                mCursorIndex = i;
                break;
            }
        }
        WatchUi.requestUpdate();
    }

    function moveCursorDown() {
        if (mTrainData == null || mTrainData.size() == 0) { return; }
        var limit = mTrainData.size();
        if (limit > mMaxVisibleTrains) { limit = mMaxVisibleTrains; }
        mCursorIndex = (mCursorIndex + 1) % limit;
        WatchUi.requestUpdate();
    }

    function moveCursorUp() {
        if (mTrainData == null || mTrainData.size() == 0) { return; }
        var limit = mTrainData.size();
        if (limit > mMaxVisibleTrains) { limit = mMaxVisibleTrains; }
        mCursorIndex = mCursorIndex - 1;
        if (mCursorIndex < 0) {
            mCursorIndex = limit - 1;
        }
        WatchUi.requestUpdate();
    }

    function confirmTrainSelection() {
        if (mTrainData == null || mCursorIndex >= mTrainData.size() || mCursorIndex >= mMaxVisibleTrains) { return; }
        var t = mTrainData[mCursorIndex];
        mFocusedTrain = {
            "dest" => t["dest"],
            "min" => t["min"],
            "depTs" => t["depTs"],
            "delay" => t["delay"],
            "plat" => t["plat"],
            "platChg" => t["platChg"]
        };
        mAppState = 2;
        mConsecutiveErrors = 0;
        // Faster timer for tracking mode (1s for seconds-precision countdown)
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 1000, true);
        }
        vibrateShort();
        enterMapView();
        WatchUi.requestUpdate();
    }

    function exitToStationView() {
        if (mMapActive) {
            mMapActive = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        mAppState = 0;
        mCursorIndex = 0;
        mFocusedTrain = null;
        mConsecutiveErrors = 0;
        // Restore normal timer rate
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 5000, true);
        }
        WatchUi.requestUpdate();
    }

    function enterMapView() {
        if (!(WatchUi has :MapTrackView)) { return; }
        if (mStationLat == null || mStationLon == null) { return; }
        if (mMapActive) { return; }

        try {
            var mapView = new WatchUi.MapTrackView();
            var stationLoc = new Position.Location(
                {:latitude => mStationLat, :longitude => mStationLon, :format => :degrees}
            );
            var marker = new WatchUi.MapMarker(stationLoc);
            marker.setIcon(WatchUi.MAP_MARKER_ICON_PIN, 0, 0);
            if (mStationName != null) {
                marker.setLabel(mStationName);
            }
            mapView.setMapMarker(marker);
            mapView.setMapMode(WatchUi.MAP_MODE_BROWSE);

            mMapActive = true;
            WatchUi.pushView(mapView, new TrainTimeMapDelegate(self), WatchUi.SLIDE_LEFT);
        } catch (e instanceof Lang.Exception) {
            mMapActive = false;
        }
    }

    function exitMapView() {
        mMapActive = false;
    }

    function updateFocusedTrain() {
        if (mAppState != 2 || mFocusedTrain == null || mTrainData == null) { return; }
        var targetDest = mFocusedTrain["dest"];
        var lastMin = mFocusedTrain["min"];
        var bestMatch = null;
        var bestDiff = 999;
        for (var i = 0; i < mTrainData.size(); i++) {
            var t = mTrainData[i];
            if (t["dest"] != null && t["dest"].equals(targetDest) && t["min"] >= -1) {
                var diff = t["min"] - lastMin;
                if (diff < 0) { diff = -diff; }
                if (diff < bestDiff) {
                    bestDiff = diff;
                    bestMatch = t;
                }
            }
        }
        if (bestMatch != null) {
            var oldPlat = mFocusedTrain["plat"];
            mFocusedTrain["min"] = bestMatch["min"];
            mFocusedTrain["depTs"] = bestMatch["depTs"];
            mFocusedTrain["delay"] = bestMatch["delay"];
            mFocusedTrain["plat"] = bestMatch["plat"];
            mFocusedTrain["platChg"] = bestMatch["platChg"];
            if (bestMatch["platChg"] && (oldPlat == null || !oldPlat.equals(bestMatch["plat"]))) {
                vibrateDouble();
            }
        } else {
            vibrateShort();
            exitToStationView();
        }
    }

    // --- Helpers ---

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

    // Bearing from point 1 to point 2 in radians (clockwise from north)
    function calculateBearing(lat1, lon1, lat2, lon2) {
        var dLon = (lon2 - lon1) * Math.PI / 180.0;
        var lat1R = lat1 * Math.PI / 180.0;
        var lat2R = lat2 * Math.PI / 180.0;
        var y = Math.sin(dLon) * Math.cos(lat2R);
        var x = Math.cos(lat1R) * Math.sin(lat2R)
              - Math.sin(lat1R) * Math.cos(lat2R) * Math.cos(dLon);
        return Math.atan2(y, x);
    }

    function getWalkMinutes() {
        if (mStationLat != null && mStationLon != null) {
            if (mLocationInfo != null && mLocationInfo.position != null) {
                var coords = mLocationInfo.position.toDegrees();
                var dist = calculateDistance(coords[0], coords[1], mStationLat, mStationLon);
                mLastWalkDist = dist;
                return dist / 83.0;
            }
            // Fallback to cached search position
            if (mLastSearchLat != null && mLastSearchLon != null) {
                var dist = calculateDistance(mLastSearchLat, mLastSearchLon, mStationLat, mStationLon);
                mLastWalkDist = dist;
                return dist / 83.0;
            }
        }
        // Fallback to last known distance (from API or previous calc)
        if (mLastWalkDist != null) {
            return mLastWalkDist / 83.0;
        }
        return null;
    }

    function clampFloat(val, minVal, maxVal) {
        if (val < minVal) { return minVal; }
        if (val > maxVal) { return maxVal; }
        return val;
    }

    function getFocusedMinutesUntil() {
        if (mFocusedTrain == null) { return 0.0; }
        var depTs = mFocusedTrain["depTs"];
        if (depTs != null) {
            return (depTs - Time.now().value()) / 60.0;
        }
        return mFocusedTrain["min"].toFloat();
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

    // --- Drawing ---

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
        var cy = 18;
        var r = 4;
        var usable = getUsableWidth(cy, width, height);
        var cx = (width + usable) / 2 - r - 4;
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

        mMaxVisibleTrains = (height < 240) ? 3 : 4;

        // GPS quality indicator
        drawGpsIndicator(dc, width, height);

        // State 2: focused tracking
        if (mAppState == 2 && mFocusedTrain != null) {
            drawFocusedMode(dc, width, height);
            return;
        }

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
                dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
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
                    var highlighted = (mAppState == 1 && i == mCursorIndex);
                    drawTrainRow(dc, mTrainData[i],
                        startY + i * rowSpacing, width, height, highlighted);
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
            // No station yet — show subtle loading text, GPS dot indicates status
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                "Loading...", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Contextual button hint at bottom
        if (mStationName != null && mTrainData != null && mTrainData.size() > 0) {
            var hintY = height * 92 / 100;
            var hintMaxW = getUsableWidth(hintY + 6, width, height) - 10;
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            var hint;
            if (mAppState == 0) {
                hint = "Press START";
            } else if (mAppState == 1) {
                hint = "START=OK  BACK";
            } else {
                hint = (WatchUi has :MapTrackView && mStationLat != null && mStationLon != null) ? "START=Map" : "";
            }
            if (!hint.equals("")) {
                dc.drawText(centerX, hintY, Graphics.FONT_XTINY,
                    truncateToFit(dc, hint, Graphics.FONT_XTINY, hintMaxW),
                    Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    function drawTrainRow(dc, train, y, width, height, highlighted) {
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

        // Highlight background for cursor in selection mode
        if (highlighted) {
            var rowCenterForBg = y + tinyH / 2;
            var usableBg = getUsableWidth(rowCenterForBg, width, height);
            var bgX = (width - usableBg) / 2 + 2;
            dc.setColor(0x004488, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, usableBg - 4, tinyH);
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, 3, tinyH);
        }

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
            dc.setColor(0xFF7700, Graphics.COLOR_TRANSPARENT);
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

    // --- Focused Mode (State 2) ---

    function drawFocusedMode(dc, width, height) {
        var centerX = width / 2;

        if (mStationName == null) { return; }

        // Station name (small, secondary)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var stationY = height * 15 / 100;
        var stationMaxW = getUsableWidth(stationY + 8, width, height) - 10;
        dc.drawText(centerX, stationY, Graphics.FONT_XTINY,
            truncateToFit(dc, mStationName, Graphics.FONT_XTINY, stationMaxW),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Destination + platform (auto-downsize, highlight platform change)
        var destY = height * 26 / 100;
        var destStr = mFocusedTrain["dest"];
        var plat = mFocusedTrain["plat"];
        var platChg = mFocusedTrain["platChg"];
        var destMaxW = getUsableWidth(destY + 10, width, height) - 10;
        var destFont = Graphics.FONT_SMALL;
        if (plat != null && !plat.equals("")) {
            destStr = destStr + "  P" + plat;
        }
        var destDims = dc.getTextDimensions(destStr, destFont);
        if (destDims[0] > destMaxW) {
            destFont = Graphics.FONT_TINY;
            destStr = truncateToFit(dc, destStr, destFont, destMaxW);
        }
        if (platChg) {
            dc.setColor(0xFF4400, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(centerX, destY, destFont,
            destStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Departure time + delay
        var minY = height * 40 / 100;
        var minutesUntil = getFocusedMinutesUntil();
        var delay = mFocusedTrain["delay"];
        if (delay == null) { delay = 0; }

        var minStr;
        if (minutesUntil < -0.5) {
            minStr = "Departed";
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        } else if (minutesUntil < 0.083) {
            minStr = "now";
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
        } else if (minutesUntil < 3.0) {
            var totalSec = (minutesUntil * 60.0).toNumber();
            var m = totalSec / 60;
            var s = totalSec % 60;
            minStr = m + ":" + (s < 10 ? "0" + s : s.toString());
            if (minutesUntil <= 2.0) {
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            }
        } else {
            minStr = minutesUntil.toNumber() + " min";
            dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(centerX, minY, Graphics.FONT_MEDIUM,
            minStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Delay indicator next to departure time
        if (delay > 0 && minutesUntil >= -0.5) {
            var minDims = dc.getTextDimensions(minStr, Graphics.FONT_MEDIUM);
            dc.setColor(0xFF7700, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX + minDims[0] / 2 + 4, minY,
                Graphics.FONT_XTINY, "+" + delay, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Tracking bar
        drawTrackingBar(dc, width, height);

        // Status text
        var statusY = height * 66 / 100;
        var walkMin = getWalkMinutes();
        if (walkMin == null) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_TINY,
                "No GPS", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var schedBuf = minutesUntil - walkMin;
            var effectBuf = schedBuf + delay;

            var statusStr;
            if (effectBuf > 0.5) {
                if (effectBuf < 1.5) {
                    var sec = (effectBuf * 60.0).toNumber();
                    statusStr = sec + "s ahead";
                } else {
                    statusStr = effectBuf.toNumber() + " min ahead";
                }
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            } else if (effectBuf < -0.5) {
                if (effectBuf > -1.5) {
                    var sec = ((-effectBuf) * 60.0).toNumber();
                    statusStr = sec + "s behind";
                } else {
                    statusStr = (-effectBuf).toNumber() + " min behind";
                }
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            } else {
                statusStr = "On time";
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            }

            var statusMaxW = getUsableWidth(statusY + 8, width, height) - 10;
            var statusFont = Graphics.FONT_TINY;
            dc.drawText(centerX, statusY, statusFont,
                truncateToFit(dc, statusStr, statusFont, statusMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Walk info at bottom
        if (mWalkInfo != null) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var walkY = height * 80 / 100;
            var walkMaxW = getUsableWidth(walkY + 8, width, height) - 10;
            dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                truncateToFit(dc, mWalkInfo, Graphics.FONT_XTINY, walkMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Direction arrow (only visible when walking)
        drawDirectionArrow(dc, width, height);
    }

    function drawTrackingBar(dc, width, height) {
        var barWidth = width * 60 / 100;
        var halfBar = barWidth / 2;
        var barX = width / 2 - halfBar;
        var barY = height * 54 / 100;
        var barH = 14;
        var midX = width / 2;

        // Background
        dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, barY, barWidth, barH);

        var walkMin = getWalkMinutes();
        if (walkMin == null) {
            // No GPS — fully gray bar
            dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barWidth, barH);
            // Midpoint marker
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX - 1, barY - 2, 2, barH + 4);
            return;
        }

        var minutesUntil = getFocusedMinutesUntil();
        var delay = mFocusedTrain["delay"];
        if (delay == null) { delay = 0; }

        var schedBuf = minutesUntil - walkMin;
        var effectBuf = schedBuf + delay;

        var barScale = 3.0;

        // Clamp to [-1, 1] then scale to pixels
        var schedFrac = clampFloat(schedBuf / barScale, -1.0, 1.0);
        var effectFrac = clampFloat(effectBuf / barScale, -1.0, 1.0);
        var schedPx = (schedFrac * halfBar).toNumber();
        var effectPx = (effectFrac * halfBar).toNumber();

        // MIP-optimized colors — distinct on 64-color palette
        var darkGreen = 0x00FF00;
        var lightGreen = 0x55FF55;
        var darkRed = 0xFF0000;
        var amber = 0xFFAA00;

        // Case 1: Both positive or zero (fully ahead)
        if (schedPx >= 0 && effectPx >= 0) {
            // Dark green: guaranteed buffer (0 to scheduledPx)
            if (schedPx > 0) {
                dc.setColor(darkGreen, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX, barY, schedPx, barH);
            }
            // Light green: delay bonus (scheduledPx to effectivePx)
            if (effectPx > schedPx) {
                dc.setColor(lightGreen, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + schedPx, barY, effectPx - schedPx, barH);
            }
        }
        // Case 3: Both negative (fully behind)
        else if (schedPx <= 0 && effectPx <= 0) {
            // Dark red: irrecoverable deficit (scheduledPx to effectivePx)
            if (schedPx < effectPx) {
                dc.setColor(darkRed, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + schedPx, barY, effectPx - schedPx, barH);
            }
            // Amber: delay recovery zone (effectivePx to 0)
            if (effectPx < 0) {
                dc.setColor(amber, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + effectPx, barY, -effectPx, barH);
            }
        }
        // Case 2: Behind on schedule but saved by delay (schedPx < 0, effectPx > 0)
        else if (schedPx < 0 && effectPx > 0) {
            // Amber: schedule deficit covered by delay
            dc.setColor(amber, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX + schedPx, barY, -schedPx, barH);
            // Light green: delay surplus right of midpoint
            dc.setColor(lightGreen, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX, barY, effectPx, barH);
        }

        // Midpoint marker
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(midX - 1, barY - 2, 2, barH + 4);
    }

    function drawDirectionArrow(dc, width, height) {
        if (mHeading == null || mStationLat == null || mStationLon == null) {
            return;
        }
        if (mLocationInfo == null || mLocationInfo.position == null) {
            return;
        }

        var coords = mLocationInfo.position.toDegrees();
        var bearing = calculateBearing(coords[0], coords[1], mStationLat, mStationLon);
        var angle = bearing - mHeading;

        var arrowCx = width / 2;
        var arrowCy = height * 89 / 100;
        var r = 12.0;

        // Arrow triangle (pointing up = bearing 0, rotated by relative angle)
        var cosA = Math.cos(angle).toFloat();
        var sinA = Math.sin(angle).toFloat();

        // Points relative to center: tip (0,-r), base-left (-0.6r, 0.5r), base-right (0.6r, 0.5r)
        var tipX = r * sinA;
        var tipY = -r * cosA;
        var blX = -r * 0.6 * cosA - r * 0.5 * sinA;
        var blY = -r * 0.6 * sinA + r * 0.5 * cosA;
        var brX = r * 0.6 * cosA - r * 0.5 * sinA;
        var brY = r * 0.6 * sinA + r * 0.5 * cosA;

        var pts = new [3];
        pts[0] = [(arrowCx + tipX).toNumber(), (arrowCy + tipY).toNumber()];
        pts[1] = [(arrowCx + blX).toNumber(), (arrowCy + blY).toNumber()];
        pts[2] = [(arrowCx + brX).toNumber(), (arrowCy + brY).toNumber()];

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // --- Station navigation ---

    function nextStation() {
        if (mStations != null && mStations.size() > 1) {
            mStationIndex = (mStationIndex + 1) % mStations.size();
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

    // --- Position & Timer ---

    function onPosition(info as Position.Info) as Void {
        // QUALITY_NOT_AVAILABLE means coordinates are garbage
        // (Fenix 6 bug: returns 0,0 instead of null)
        // QUALITY_LAST_KNOWN and above are valid (cached or live)
        if (info == null || info.position == null
                || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            if (mStationId == null && !mLoadedFromCache) {
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

        // Update heading when moving; keep last known heading when stationary
        if (info.speed != null && info.speed > 0.5 && info.heading != null) {
            mHeading = info.heading;
        }

        // Persist location to Storage for next app launch
        Storage.setValue("lastLat", lat.toFloat());
        Storage.setValue("lastLon", lon.toFloat());

        // Switzerland bounding box check — don't clear loaded stations (border hysteresis)
        if (lat < 45.8 || lat > 47.8 || lon < 5.9 || lon > 10.5) {
            if (mStationId == null) {
                mStatus = "Not in Switzerland";
                WatchUi.requestUpdate();
            }
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

    function onTimerTick() as Void {
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
                    if (mStationId == null) {
                        mStatus = "Not in Switzerland";
                        WatchUi.requestUpdate();
                    }
                    return;
                }

                // Re-search stations if moved >500m from last search
                if (hasMovedSignificantly(lat, lon)) {
                    clearStationState();
                    mRequestInFlight = true;
                    mRequestStartTime = Time.now().value();
                    fetchTrainData(lat, lon);
                }
            }
        }

        // Update walk distance every tick (5s)
        updateWalkDistance();

        // Heartbeat vibration when behind schedule in tracking mode
        if (mAppState == 2 && mFocusedTrain != null) {
            var focusedMin = getFocusedMinutesUntil();
            // Auto-exit when train has departed for >1 minute
            if (focusedMin < -1.0) {
                vibrateShort();
                exitToStationView();
            } else {
                var walkMin = getWalkMinutes();
                if (walkMin != null) {
                    var delay = mFocusedTrain["delay"];
                    if (delay == null) { delay = 0; }
                    var effectBuf = focusedMin - walkMin + delay;
                    var vibeNow = Time.now().value();
                    if (effectBuf < -0.5) {
                        var interval = (effectBuf < -2.0) ? 2 : 4;
                        if (vibeNow - mLastVibeTick >= interval) {
                            mLastVibeTick = vibeNow;
                            vibrateHeartbeat();
                        }
                    }
                }
            }
        }

        if (mRequestInFlight) {
            WatchUi.requestUpdate();
            return;
        }

        // Fetch stationboard based on elapsed time (>= 10s since last)
        var nowFetch = Time.now().value();
        if (nowFetch - mLastFetchTime >= 10) {
            if (mStationId != null) {
                mLastFetchTime = nowFetch;
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                fetchStationboard(mStationId);
            } else if (mLocationInfo != null && mLocationInfo.position != null) {
                mLastFetchTime = nowFetch;
                mStatus = "Finding stations...";
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                var coords = mLocationInfo.position.toDegrees();
                fetchTrainData(coords[0], coords[1]);
            }
        }

        WatchUi.requestUpdate();
    }

    // --- Network ---

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

        Communications.makeWebRequest(url, null, params, method(:onStationsReceived));
    }

    function onStationsReceived(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        mRequestInFlight = false;
        mRequestStartTime = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary && data.hasKey("stations")) {
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
                    var entry = parseStationEntry(s);
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

                // If no train stations found in coordinate search,
                // search by name to find the nearest train station
                if (mTrainStations.size() == 0) {
                    var cityName = extractCityName();
                    if (cityName != null) {
                        fetchTrainStationsByName(cityName);
                    }
                }

                // Build available modes and select station
                rebuildModesAndSelect();
            } else {
                mStatus = "No stations nearby";
                mTrainData = null;
            }
        } else if (responseCode == 429) {
            mStatus = "Rate limited";
        } else {
            mStatus = "Station error: " + responseCode;
            mTrainData = null;
        }
        WatchUi.requestUpdate();
    }

    function rebuildModesAndSelect() {
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
        }
    }

    function extractCityName() {
        // Swiss stops follow "City, Stop Name" format
        var stations = mBusStations.size() > 0 ? mBusStations : mTramStations;
        if (stations.size() == 0) { return null; }
        var name = stations[0]["label"];
        var commaIdx = name.find(",");
        if (commaIdx != null && commaIdx > 0) {
            return name.substring(0, commaIdx);
        }
        return name;
    }

    function fetchTrainStationsByName(cityName) {
        var url = "https://transport.opendata.ch/v1/locations";

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {}
        };

        Communications.makeWebRequest(url, {"query" => cityName, "type" => "station"}, params, method(:onTrainStationsReceived));
    }

    function onTrainStationsReceived(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Lang.Dictionary) || !data.hasKey("stations")) {
            return;
        }

        var stations = data["stations"];
        if (stations == null) { return; }

        for (var i = 0; i < stations.size(); i++) {
            var s = stations[i];
            if (!s.hasKey("id") || s["id"] == null) { continue; }

            var icon = "";
            if (s.hasKey("icon") && s["icon"] != null) {
                icon = s["icon"].toString();
            }
            // Only add non-bus, non-tram stations (trains, S-Bahn, etc.)
            if (icon.equals("bus") || icon.equals("tram")) { continue; }

            var entry = parseStationEntry(s);
            var sLat = entry["lat"];
            var sLon = entry["lon"];

            // Calculate distance from user position (or cached position)
            var dist = 0;
            if (sLat != null && sLon != null) {
                if (mLocationInfo != null && mLocationInfo.position != null) {
                    var coords = mLocationInfo.position.toDegrees();
                    dist = calculateDistance(coords[0], coords[1], sLat, sLon);
                } else if (mLastSearchLat != null && mLastSearchLon != null) {
                    dist = calculateDistance(mLastSearchLat, mLastSearchLon, sLat, sLon);
                }
            }

            // Only add stations within 5km
            if (dist > 5000) { continue; }
            entry["dist"] = dist;
            if (mTrainStations.size() < 5) {
                mTrainStations.add(entry);
            }
        }

        if (mTrainStations.size() > 0) {
            // Rebuild modes to include trains
            var hadTrain = false;
            for (var i = 0; i < mAvailableModes.size(); i++) {
                if (mAvailableModes[i] == 0) { hadTrain = true; }
            }
            if (!hadTrain) {
                // Insert train at beginning so it appears first
                var newModes = [0];
                for (var i = 0; i < mAvailableModes.size(); i++) {
                    newModes.add(mAvailableModes[i]);
                }
                mAvailableModes = newModes;
            }
            // Only auto-switch if in station view — don't disrupt active tracking
            if (mAppState == 0) {
                mCurrentMode = 0;
                mStations = getStationsForMode(0);
                if (mStations != null && mStations.size() > 0) {
                    mStationIndex = 0;
                    selectStation(0);
                }
            }
        }
    }

    function fetchStationboard(stationId) {
        var url = "https://transport.opendata.ch/v1/stationboard"
            + "?fields[]=stationboard/to"
            + "&fields[]=stationboard/category"
            + "&fields[]=stationboard/stop/departureTimestamp"
            + "&fields[]=stationboard/stop/delay"
            + "&fields[]=stationboard/stop/platform"
            + "&fields[]=stationboard/stop/prognosis/platform";

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {}
        };

        Communications.makeWebRequest(url, {"id" => stationId, "limit" => "5"}, params, method(:onTrainDataReceived));
    }

    function onTrainDataReceived(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        mRequestInFlight = false;
        mRequestStartTime = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary && data.hasKey("stationboard")) {
            mConsecutiveErrors = 0;
            mTrainData = [];
            var departures = data["stationboard"];
            var nowSeconds = Time.now().value();

            for (var i = 0; i < departures.size() && i < 5; i++) {
                var departure = departures[i];
                var destination = (departure.hasKey("to") && departure["to"] != null) ? departure["to"] : "?";
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
                    "depTs" => (departure.hasKey("stop") && departure["stop"].hasKey("departureTimestamp")) ? departure["stop"]["departureTimestamp"] : null,
                    "delay" => delay,
                    "plat" => platform,
                    "platChg" => platformChanged,
                    "dest" => destination
                });
            }

            if (mStationName != null) {
                mStatus = mStationName;
            }

            // Clamp cursor in selection mode
            if (mAppState == 1) {
                var limit = mTrainData.size();
                if (limit > mMaxVisibleTrains) { limit = mMaxVisibleTrains; }
                if (limit == 0) {
                    exitToStationView();
                } else if (mCursorIndex >= limit) {
                    mCursorIndex = limit - 1;
                }
            }

            // Update focused train in tracking mode
            updateFocusedTrain();
        } else {
            if (mAppState == 2) {
                // Tolerate transient errors in tracking mode
                mConsecutiveErrors = mConsecutiveErrors + 1;
                if (mConsecutiveErrors >= 3) {
                    mTrainData = null;
                    if (responseCode == 429) {
                        mStatus = "Rate limited";
                    } else {
                        mStatus = "Error: " + responseCode;
                    }
                    exitToStationView();
                }
            } else {
                if (responseCode == 429) {
                    mStatus = "Rate limited";
                } else {
                    mStatus = "Error: " + responseCode;
                }
                mTrainData = null;
                if (mAppState > 0) {
                    exitToStationView();
                }
            }
        }
        WatchUi.requestUpdate();
    }

    function formatWalkInfo(distanceMeters) {
        var dist = distanceMeters.toNumber();
        mLastWalkDist = dist;
        var walkMinutes = (dist / 83.0).toNumber();
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

    function parseStationEntry(s) {
        var sLat = null;
        var sLon = null;
        if (s.hasKey("coordinate") && s["coordinate"] != null) {
            var coord = s["coordinate"];
            if (coord.hasKey("x")) { sLat = coord["x"]; }
            if (coord.hasKey("y")) { sLon = coord["y"]; }
        }
        return {
            "id" => s["id"],
            "label" => s.hasKey("name") ? s["name"] : "Station",
            "dist" => (s.hasKey("distance") && s["distance"] != null) ? s["distance"] : 0,
            "lat" => sLat,
            "lon" => sLon
        };
    }

    function vibrateShort() {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 50)]);
        }
    }

    function vibrateDouble() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 50),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 50)
            ]);
        }
    }

    function vibrateHeartbeat() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(50, 50),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(50, 50)
            ]);
        }
    }
}
