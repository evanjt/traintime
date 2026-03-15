using Toybox.WatchUi;
using Toybox.Position;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Application.Storage;

class TrainTimeView extends WatchUi.View {

    var mLocationInfo;
    var mTrainData;
    var mTimer;
    var mStatus;
    var mStationId;
    var mStationName;
    var mRequestInFlight;
    var mWalkInfo;
    var mStations;
    var mStationIndex;
    var mLastSearchLat;
    var mLastSearchLon;
    var mRequestStartTime;
    var mTrainStations;
    var mBusStations;
    var mTramStations;
    var mSpecialStations;
    var mCurrentMode;
    var mAvailableModes;
    var mGpsQuality;
    var mLoadedFromCache;
    var mStationLat;
    var mStationLon;
    var mTickCount;
    var mLastWalkDist;  // last known walk distance in meters
    // 0 = station view, 1 = train selection, 2 = focused tracking, 3 = inactive
    var mAppState;
    var mCursorIndex;
    var mFocusedTrain;
    var mHeading;  // GPS heading in radians, null when stationary
    var mLastFetchTime;
    var mConsecutiveErrors;
    var mLastVibeTick;
    var mMaxVisibleTrains;
    var mScrollOffset;  // first visible row index for scrolling in State 1
    var mMapActive;  // true when MapTrackView is pushed

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
        mSpecialStations = null;
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
        mScrollOffset = 0;
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

        // Set initial status when no station and no activity
        if (mStationId == null && !mRequestInFlight && !mLoadedFromCache) {
            mStatus = "Waiting for GPS...";
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
                ApiHandler.fetchStations(self, savedLat, savedLon);
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

    function onUpdate(dc) {
        Renderer.render(dc, self);
    }

    // --- API callback stubs ---

    function onStationsReceived(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        ApiHandler.handleStationsResponse(self, responseCode, data);
    }

    function onTrainDataReceived(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        ApiHandler.handleDeparturesResponse(self, responseCode, data);
    }

    // --- State management ---

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
        mSpecialStations = null;
        mTrainData = null;
        mWalkInfo = null;
        mStationIndex = 0;
        mAvailableModes = [];
        mStationLat = null;
        mStationLon = null;
        mLastWalkDist = null;
        mAppState = 0;
        mCursorIndex = 0;
        mScrollOffset = 0;
        mFocusedTrain = null;
    }

    function getStationsForMode(mode) {
        if (mode == 0) { return mTrainStations; }
        if (mode == 1) { return mBusStations; }
        if (mode == 2) { return mTramStations; }
        if (mode == 3) { return mSpecialStations; }
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

    function cycleModeReverse() {
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
        idx = idx - 1;
        if (idx < 0) { idx = mAvailableModes.size() - 1; }
        mCurrentMode = mAvailableModes[idx];
        mStations = getStationsForMode(mCurrentMode);
        if (mStations != null && mStations.size() > 0) {
            mStationIndex = 0;
            selectStation(0);
        }
    }

    function getAppState() {
        return mAppState;
    }

    function enterTrainSelection() {
        if (mStationName == null) {
            return;
        }
        mAppState = 1;
        mCursorIndex = -1;  // start on station indicator
        mScrollOffset = 0;
        WatchUi.requestUpdate();
    }

    function moveCursorDown() {
        if (mTrainData == null || mTrainData.size() == 0) {
            // No departures — only station indicator navigable
            return;
        }
        var total = mTrainData.size();
        if (mCursorIndex == -1) {
            // Move from station indicator to first departure row
            mCursorIndex = 0;
            mScrollOffset = 0;
        } else {
            mCursorIndex = mCursorIndex + 1;
            if (mCursorIndex >= total) {
                // Wrap to station indicator
                mCursorIndex = -1;
            }
        }
        // Scroll adjustment (only for departure rows)
        if (mCursorIndex >= 0) {
            if (mCursorIndex >= mScrollOffset + mMaxVisibleTrains) {
                mScrollOffset = mCursorIndex - mMaxVisibleTrains + 1;
            }
            if (mCursorIndex < mScrollOffset) {
                mScrollOffset = 0;
            }
        }
        WatchUi.requestUpdate();
    }

    function moveCursorUp() {
        if (mTrainData == null || mTrainData.size() == 0) { return; }
        if (mCursorIndex == -1) {
            // Already at top (station indicator), no-op
            return;
        }
        mCursorIndex = mCursorIndex - 1;
        // mCursorIndex can be -1 here (station indicator)
        if (mCursorIndex >= 0 && mCursorIndex < mScrollOffset) {
            mScrollOffset = mCursorIndex;
        }
        WatchUi.requestUpdate();
    }

    function confirmTrainSelection() {
        if (mTrainData == null || mCursorIndex < 0 || mCursorIndex >= mTrainData.size()) { return; }
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
        mLastFetchTime = 0;  // Force immediate fetch on tracking entry
        // Faster timer for tracking mode (1s for seconds-precision countdown)
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 1000, true);
        }
        Haptics.vibrateShort();
        WatchUi.requestUpdate();
    }

    function exitToStationView() {
        if (mMapActive) {
            mMapActive = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        mAppState = 0;
        mCursorIndex = 0;
        mScrollOffset = 0;
        mFocusedTrain = null;
        mConsecutiveErrors = 0;
        // Restore normal timer rate
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 5000, true);
        }
        WatchUi.requestUpdate();
    }

    function enterInactiveState() {
        if (mMapActive) {
            mMapActive = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        mAppState = 3;
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
                Haptics.vibrateDouble();
            }
        } else {
            Haptics.vibrateShort();
            enterInactiveState();
        }
    }

    // --- Walk calculations ---

    function getWalkMinutes() {
        if (mStationLat != null && mStationLon != null) {
            if (mLocationInfo != null && mLocationInfo.position != null) {
                var coords = mLocationInfo.position.toDegrees();
                var dist = GeoMath.calculateDistance(coords[0], coords[1], mStationLat, mStationLon);
                mLastWalkDist = dist;
                return dist / 83.0;
            }
            // Fallback to cached search position
            if (mLastSearchLat != null && mLastSearchLon != null) {
                var dist = GeoMath.calculateDistance(mLastSearchLat, mLastSearchLon, mStationLat, mStationLon);
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
        var dist = GeoMath.calculateDistance(coords[0], coords[1], mStationLat, mStationLon);
        mWalkInfo = formatWalkInfo(dist);
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

    // --- Station navigation ---

    function nextStation() {
        if (mStations != null && mStations.size() > 1) {
            mStationIndex = (mStationIndex + 1) % mStations.size();
            selectStation(mStationIndex);
        }
    }

    function cycleStation() {
        nextStation();
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

        // Use embedded departures if available (closest station per mode)
        if (station.hasKey("departures") && station["departures"] != null
                && station["departures"].size() > 0) {
            mTrainData = ApiHandler.parseDepartureArray(station["departures"]);
            mLastFetchTime = Time.now().value();
            mRequestInFlight = false;
            mRequestStartTime = null;
        } else {
            mRequestInFlight = true;
            mRequestStartTime = Time.now().value();
            ApiHandler.fetchDepartures(self, mStationId);
        }
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
                ApiHandler.fetchStations(self, lat, lon);
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
            ApiHandler.fetchStations(self, lat, lon);
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
                    ApiHandler.fetchStations(self, lat, lon);
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
                Haptics.vibrateShort();
                enterInactiveState();
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
                            Haptics.vibrateHeartbeat();
                        }
                    }
                }
            }
        }

        if (mRequestInFlight) {
            WatchUi.requestUpdate();
            return;
        }

        // Skip API fetches in inactive state
        if (mAppState == 3) {
            WatchUi.requestUpdate();
            return;
        }

        // Fetch stationboard based on elapsed time
        var nowFetch = Time.now().value();
        var fetchCooldown = mAppState == 2 ? 10 : 30;
        if (nowFetch - mLastFetchTime >= fetchCooldown) {
            if (mStationId != null) {
                mLastFetchTime = nowFetch;
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                ApiHandler.fetchDepartures(self, mStationId);
            } else if (mLocationInfo != null && mLocationInfo.position != null) {
                mLastFetchTime = nowFetch;
                mStatus = "Finding stations...";
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                var coords = mLocationInfo.position.toDegrees();
                ApiHandler.fetchStations(self, coords[0], coords[1]);
            }
        }

        WatchUi.requestUpdate();
    }
}
