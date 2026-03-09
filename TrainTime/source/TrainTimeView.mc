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
    // 0 = station view, 1 = train selection, 2 = focused tracking
    private var mAppState;
    private var mCursorIndex;
    private var mFocusedTrain;

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
        mAppState = 0;
        mCursorIndex = 0;
        mFocusedTrain = null;
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
        WatchUi.requestUpdate();
    }

    function moveCursorDown() {
        if (mTrainData == null || mTrainData.size() == 0) { return; }
        mCursorIndex = (mCursorIndex + 1) % mTrainData.size();
        WatchUi.requestUpdate();
    }

    function moveCursorUp() {
        if (mTrainData == null || mTrainData.size() == 0) { return; }
        mCursorIndex = mCursorIndex - 1;
        if (mCursorIndex < 0) {
            mCursorIndex = mTrainData.size() - 1;
        }
        WatchUi.requestUpdate();
    }

    function confirmTrainSelection() {
        if (mTrainData == null || mCursorIndex >= mTrainData.size()) { return; }
        var t = mTrainData[mCursorIndex];
        mFocusedTrain = {
            "dest" => t["dest"],
            "min" => t["min"],
            "delay" => t["delay"],
            "plat" => t["plat"],
            "platChg" => t["platChg"]
        };
        mAppState = 2;
        WatchUi.requestUpdate();
    }

    function exitToStationView() {
        mAppState = 0;
        mCursorIndex = 0;
        mFocusedTrain = null;
        WatchUi.requestUpdate();
    }

    function updateFocusedTrain() {
        if (mAppState != 2 || mFocusedTrain == null || mTrainData == null) { return; }
        var targetDest = mFocusedTrain["dest"];
        var lastMin = mFocusedTrain["min"];
        var bestMatch = null;
        var bestDiff = 999;
        for (var i = 0; i < mTrainData.size(); i++) {
            var t = mTrainData[i];
            if (t["dest"].equals(targetDest) && t["min"] >= -1) {
                var diff = t["min"] - lastMin;
                if (diff < 0) { diff = -diff; }
                if (diff < bestDiff) {
                    bestDiff = diff;
                    bestMatch = t;
                }
            }
        }
        if (bestMatch != null) {
            mFocusedTrain["min"] = bestMatch["min"];
            mFocusedTrain["delay"] = bestMatch["delay"];
            mFocusedTrain["plat"] = bestMatch["plat"];
            mFocusedTrain["platChg"] = bestMatch["platChg"];
        } else {
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

    function getWalkMinutes() {
        if (mStationLat == null || mStationLon == null) { return null; }
        if (mLocationInfo == null || mLocationInfo.position == null) { return null; }
        var coords = mLocationInfo.position.toDegrees();
        var dist = calculateDistance(coords[0], coords[1], mStationLat, mStationLon);
        return dist / 83.0;
    }

    function clampFloat(val, minVal, maxVal) {
        if (val < minVal) { return minVal; }
        if (val > maxVal) { return maxVal; }
        return val;
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
            dc.setColor(0x003366, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, usableBg - 4, tinyH);
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

    // --- Focused Mode (State 2) ---

    function drawFocusedMode(dc, width, height) {
        var centerX = width / 2;

        // Station name
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var stationY = height * 15 / 100;
        var stationMaxW = getUsableWidth(stationY + 10, width, height) - 10;
        dc.drawText(centerX, stationY, Graphics.FONT_SMALL,
            truncateToFit(dc, mStationName, Graphics.FONT_SMALL, stationMaxW),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Destination + platform
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var destY = height * 28 / 100;
        var destStr = mFocusedTrain["dest"];
        var plat = mFocusedTrain["plat"];
        if (plat != null && !plat.equals("")) {
            destStr = destStr + "  P" + plat;
        }
        var destMaxW = getUsableWidth(destY + 10, width, height) - 10;
        dc.drawText(centerX, destY, Graphics.FONT_SMALL,
            truncateToFit(dc, destStr, Graphics.FONT_SMALL, destMaxW),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Departure time + delay
        var minY = height * 40 / 100;
        var minutesUntil = mFocusedTrain["min"];
        var delay = mFocusedTrain["delay"];
        if (delay == null) { delay = 0; }

        var minStr;
        if (minutesUntil <= 0) {
            minStr = "now";
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
        } else {
            minStr = minutesUntil + " min";
            if (minutesUntil <= 2) {
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            }
        }
        dc.drawText(centerX, minY, Graphics.FONT_MEDIUM,
            minStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Delay indicator next to departure time
        if (delay > 0) {
            var minDims = dc.getTextDimensions(minStr, Graphics.FONT_MEDIUM);
            var smallH = dc.getFontHeight(Graphics.FONT_SMALL);
            var medH = minDims[1];
            dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX + minDims[0] / 2 + 4, minY + (medH - smallH) / 2,
                Graphics.FONT_SMALL, "+" + delay, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Tracking bar
        drawTrackingBar(dc, width, height);

        // Status text
        var statusY = height * 66 / 100;
        var walkMin = getWalkMinutes();
        if (walkMin == null) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_SMALL,
                "No GPS", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var schedBuf = minutesUntil - walkMin;
            var effectBuf = schedBuf + delay;

            var statusStr;
            if (effectBuf > 0.5) {
                var ahead = effectBuf.toNumber();
                if (ahead < 1) { ahead = 1; }
                statusStr = ahead + " min ahead";
                if (delay > 0) {
                    statusStr = statusStr + " (+" + delay + " delay)";
                }
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            } else if (effectBuf < -0.5) {
                var behind = (-effectBuf).toNumber();
                if (behind < 1) { behind = 1; }
                statusStr = behind + " min behind";
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            } else {
                statusStr = "On time";
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            }

            var statusMaxW = getUsableWidth(statusY + 10, width, height) - 10;
            dc.drawText(centerX, statusY, Graphics.FONT_SMALL,
                truncateToFit(dc, statusStr, Graphics.FONT_SMALL, statusMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Walk info at bottom
        if (mWalkInfo != null) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var walkY = height * 82 / 100;
            var walkMaxW = getUsableWidth(walkY + 8, width, height) - 10;
            dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                truncateToFit(dc, mWalkInfo, Graphics.FONT_XTINY, walkMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawTrackingBar(dc, width, height) {
        var barWidth = width * 60 / 100;
        var halfBar = barWidth / 2;
        var barX = width / 2 - halfBar;
        var barY = height * 54 / 100;
        var barH = 10;
        var midX = width / 2;

        // Background
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, barY, barWidth, barH);

        var walkMin = getWalkMinutes();
        if (walkMin == null) {
            // No GPS — fully gray bar
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barWidth, barH);
            // Midpoint marker
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX - 1, barY - 2, 2, barH + 4);
            return;
        }

        var minutesUntil = mFocusedTrain["min"];
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

        // Determine stale GPS for muted colors
        var isStale = (mLoadedFromCache || mGpsQuality == Position.QUALITY_LAST_KNOWN);

        var darkGreen = isStale ? 0x336633 : 0x00CC00;
        var lightGreen = isStale ? 0x2A4D2A : 0x009900;
        var darkRed = isStale ? 0x663333 : 0xFF0000;
        var lightRed = isStale ? 0x4D2A2A : 0xCC4400;

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
            // Dark red: definite deficit (effectivePx to 0)
            if (effectPx < 0) {
                dc.setColor(darkRed, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + effectPx, barY, -effectPx, barH);
            }
            // Light red: extra risk if delay shrinks (scheduledPx to effectivePx)
            if (schedPx < effectPx) {
                dc.setColor(lightRed, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + schedPx, barY, effectPx - schedPx, barH);
            }
        }
        // Case 2: Behind on schedule but saved by delay (schedPx < 0, effectPx > 0)
        else if (schedPx < 0 && effectPx > 0) {
            // Dark red: schedule deficit left of midpoint
            dc.setColor(darkRed, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX + schedPx, barY, -schedPx, barH);
            // Light green: delay surplus right of midpoint
            dc.setColor(lightGreen, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX, barY, effectPx, barH);
        }

        // Midpoint marker
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(midX - 1, barY - 2, 2, barH + 4);
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

        Communications.makeWebRequest(url, null, params, method(:onTrainDataReceived));
    }

    function onTrainDataReceived(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
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

            // Clamp cursor in selection mode
            if (mAppState == 1) {
                if (mTrainData.size() == 0) {
                    exitToStationView();
                } else if (mCursorIndex >= mTrainData.size()) {
                    mCursorIndex = mTrainData.size() - 1;
                }
            }

            // Update focused train in tracking mode
            updateFocusedTrain();
        } else {
            if (responseCode == 429) {
                mStatus = "Rate limited";
            } else {
                mStatus = "Error: " + responseCode;
            }
            mTrainData = null;

            // Exit sub-states on error
            if (mAppState > 0) {
                exitToStationView();
            }
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
