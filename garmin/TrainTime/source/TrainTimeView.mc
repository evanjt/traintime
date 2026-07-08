using Toybox.WatchUi;
using Toybox.Position;
using Toybox.Timer;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.PersistedContent;
using Toybox.System;

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
    var mModeChangedTime;  // drives the transient mode-name label
    var mHintTime;         // drives the transient button labels next to the arcs
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
    var mLastInteractionTime;
    var mFormationClasses;  // Array of Number (1 or 2) per wagon
    var mFormationNumbers;  // Array of Number (wagon numbers)
    var mFormationSectors;  // Array of String (sector letters)
    var mFavouriteData; // favourite departures from API (separate from mTrainData)
    var mToast;             // short-lived message overlay in the tracking view
    var mToastTick;         // timestamp when the toast was set
    var mReminderQueuedTs;  // when the pending reminder was queued (escalation timer)
    var mReminderNotified;  // "will send later" toast shown for the current reminder
    var mManualStation; // true when a station was picked via quick-launch (suppress GPS re-search)
    var mPendingFavTrack; // {line, dest} awaiting a fetch to jump into tracking
    var mPhoneLat;        // last location pushed by the phone (backfill when watch GPS is weak)
    var mPhoneLon;
    var mPhoneLocTs;      // epoch seconds the phone location arrived
    var mLastLocRequestTs; // epoch seconds we last asked the phone for its location (throttle)
    var mLastAliveTs;      // epoch seconds we last sent a liveness heartbeat to the phone

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
        var savedMode = Storage.getValue("defaultMode");
        if (savedMode != null && savedMode >= 0 && savedMode <= 2) {
            mCurrentMode = savedMode;
        }
        mAvailableModes = [];
        mGpsQuality = Position.QUALITY_NOT_AVAILABLE;
        mLoadedFromCache = false;
        mStationLat = null;
        mStationLon = null;
        mTickCount = 0;
        mLastWalkDist = null;
        mPhoneLat = null;
        mPhoneLon = null;
        mPhoneLocTs = null;
        mLastLocRequestTs = null;
        mLastAliveTs = null;
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
        mLastInteractionTime = 0;
        mFormationClasses = null;
        mFormationNumbers = null;
        mFormationSectors = null;
        mFavouriteData = null;
        mToast = null;
        mToastTick = null;
        mReminderQueuedTs = null;
        mReminderNotified = true;
        mManualStation = false;
        mPendingFavTrack = null;
        mHintTime = null;
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    function onShow() {
        PhoneSync.activate();

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

        // Only set interaction time on first launch, not on wrist-raise wake cycles
        // (onShow is called each time the display wakes, which would reset the inactivity timer)
        if (mLastInteractionTime == 0) {
            mLastInteractionTime = Time.now().value();
            mHintTime = mLastInteractionTime;
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
        mFavouriteData = null;
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
        mManualStation = false;
        mPendingFavTrack = null;
    }

    // A fresh station search is being adopted: drop selection/tracking leftovers
    // and stale departures, but keep nothing else — the caller replaces the
    // station groups right after. Unlike clearStationState this never runs
    // before the response, so a failed re-search can't strand the app stateless.
    function resetForNewStations() {
        if (mMapActive) {
            mMapActive = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        mAppState = 0;
        mCursorIndex = 0;
        mScrollOffset = 0;
        mFocusedTrain = null;
        mPendingFavTrack = null;
        mTrainData = null;
        mFavouriteData = null;
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
        mModeChangedTime = Time.now().value();
        mHintTime = mModeChangedTime;
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
        mModeChangedTime = Time.now().value();
        mHintTime = mModeChangedTime;
        mStations = getStationsForMode(mCurrentMode);
        if (mStations != null && mStations.size() > 0) {
            mStationIndex = 0;
            selectStation(0);
        }
    }

    function getAppState() {
        return mAppState;
    }

    // Combined selectable count: favourites + regular departures
    function getSelectableCount() {
        var count = 0;
        if (mFavouriteData != null) { count = count + mFavouriteData.size(); }
        if (mTrainData != null) { count = count + mTrainData.size(); }
        return count;
    }

    // Get item from combined list: favourites first, then regular departures
    function getSelectableItem(index) {
        var favCount = (mFavouriteData != null) ? mFavouriteData.size() : 0;
        if (index < favCount) {
            return mFavouriteData[index];
        }
        return mTrainData[index - favCount];
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
        var total = getSelectableCount();
        if (total == 0) {
            return;
        }
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
        var total = getSelectableCount();
        if (total == 0) { return; }
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
        var total = getSelectableCount();
        if (total == 0 || mCursorIndex < 0 || mCursorIndex >= total) { return; }
        var t = getSelectableItem(mCursorIndex);
        mFocusedTrain = {
            "dest" => t["dest"],
            "min" => t["min"],
            "depTs" => t["depTs"],
            "delay" => t["delay"],
            "plat" => t["plat"],
            "platChg" => t["platChg"],
            "line" => t["line"],
            "cat" => t["cat"],
            "trainNum" => t["trainNum"],
            "opRef" => t["opRef"]
        };
        mAppState = 2;
        // Reformat walk info without station index
        if (mLastWalkDist != null) {
            mWalkInfo = formatWalkInfo(mLastWalkDist);
        }
        mConsecutiveErrors = 0;
        mLastFetchTime = 0;  // Force immediate fetch on tracking entry
        maybeFetchFormation(t);

        // Faster timer for tracking mode (1s for seconds-precision countdown)
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 1000, true);
        }
        Haptics.vibrateShort();
        PhoneSync.sendTrackStarted(mFocusedTrain, mStationId);
        // Only user-initiated tracking counts toward the review ask; a
        // phone-pushed track command doesn't route through here.
        ReviewPrompt.incrementTrackCount();
        WatchUi.requestUpdate();
    }

    // Ask the phone to save the focused departure as a reminder. Needs the origin
    // station's coords (the phone's distance-aware reminder is computed from them).
    // The payload goes into the outbox first: delivery is only certain once the
    // phone app acks, everything before that is best-effort.
    function remindOnPhone() {
        if (mFocusedTrain == null || mStationId == null ||
            mStationLat == null || mStationLon == null) {
            return;
        }
        var stationName = mStationName != null ? mStationName : "Station";
        var payload = PhoneSync.buildSaveReminder(mFocusedTrain, mStationId, stationName,
            mStationLat, mStationLon);
        if (payload == null) { return; }
        var now = Time.now().value();
        ReminderQueue.enqueue(payload, payload["id"], now);
        mReminderQueuedTs = now;
        mReminderNotified = false;
        PhoneSync.transmit(payload);
        Haptics.vibrateShort();
        showToast("Sending to phone...");
    }

    // The phone pushed its favourites. Outer-join them into local storage. No
    // push-back: the phone carries our favourites via its own change-push and the
    // re-seed on watch-open, so applying never triggers a sync loop.
    function applyFavouritesFromPhone(data) {
        var favs = data.hasKey("favs") ? data["favs"] : null;
        if (FavouritesManager.applyUnionFromSync(favs)) {
            WatchUi.requestUpdate();
        }
    }

    function isRailCategory(cat) {
        return cat.equals("IR") || cat.equals("IC") || cat.equals("EC") || cat.equals("ICE")
            || cat.equals("TGV") || cat.equals("RJX") || cat.equals("RE") || cat.equals("R")
            || cat.equals("S") || cat.equals("PE") || cat.equals("NJ") || cat.equals("EN");
    }

    // Reset any previous formation and fetch the new one for rail departures.
    // Shared by every tracking entry: local selection, pending favourite and
    // phone-pushed track. Non-rail or missing fields just leave it cleared.
    function maybeFetchFormation(t) {
        mFormationClasses = null;
        mFormationNumbers = null;
        mFormationSectors = null;
        var trainNum = t["trainNum"];
        var cat = t["cat"];
        if (trainNum != null && cat != null && isRailCategory(cat) && mStationId != null) {
            ApiHandler.fetchFormation(self, trainNum, mStationId, t["opRef"]);
        }
    }

    function onFormationReceived(responseCode, data) {
        ApiHandler.handleFormationResponse(self, responseCode, data);
    }

    function exitToStationView() {
        var wasTracking = (mAppState == 2);
        if (mMapActive) {
            mMapActive = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        mAppState = 0;
        mLastInteractionTime = Time.now().value();
        mCursorIndex = 0;
        mScrollOffset = 0;
        mFocusedTrain = null;
        mFormationClasses = null;
        mFormationNumbers = null;
        mFormationSectors = null;
        mConsecutiveErrors = 0;
        // Restore normal timer rate
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 5000, true);
        }
        // Ask here, not at tracking entry, so the prompt never covers a live
        // countdown. The gate makes this rare.
        if (wasTracking) {
            ReviewPrompt.maybeShow();
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
        mFormationClasses = null;
        mFormationNumbers = null;
        mFormationSectors = null;
        mConsecutiveErrors = 0;
        // Restore normal timer rate
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 5000, true);
        }
        WatchUi.requestUpdate();
    }

    function enterMapView() {
        if (mStationLat == null || mStationLon == null) {
            showToast("No station location");
            return;
        }

        var stationLoc = new Position.Location(
            {:latitude => mStationLat, :longitude => mStationLon, :format => :degrees}
        );

        // Primary: native navigation via saved waypoint
        if (Toybox has :PersistedContent) {
            try {
                // Clean up old waypoints from this app
                var iter = PersistedContent.getAppWaypoints();
                var old = iter.next();
                while (old != null) {
                    old.remove();
                    old = iter.next();
                }

                // Save station as waypoint and navigate
                var name = mStationName != null ? mStationName : "Station";
                PersistedContent.saveWaypoint(stationLoc, {:name => name});
                iter = PersistedContent.getAppWaypoints();
                var wp = iter.next();
                if (wp != null) {
                    System.exitTo(wp.toIntent());
                    return;
                }
            } catch (e) {
                // Fall through to MapTrackView fallback
            }
        }

        // Fallback: MapTrackView with polyline
        if (!(WatchUi has :MapTrackView)) {
            showToast("Navigation unavailable");
            return;
        }
        if (mMapActive) { return; }

        try {
            var mapView = new WatchUi.MapTrackView();
            var marker = new WatchUi.MapMarker(stationLoc);
            marker.setIcon(WatchUi.MAP_MARKER_ICON_PIN, 0, 0);
            if (mStationName != null) {
                marker.setLabel(mStationName);
            }
            mapView.setMapMarker(marker);

            // Add route polyline from user position to station
            if (WatchUi has :MapPolyline) {
                if (mLocationInfo != null && mLocationInfo.position != null) {
                    var coords = mLocationInfo.position.toDegrees();
                    var userLoc = new Position.Location(
                        {:latitude => coords[0], :longitude => coords[1], :format => :degrees}
                    );
                    var polyline = new WatchUi.MapPolyline();
                    polyline.addLocation(userLoc);
                    polyline.addLocation(stationLoc);
                    polyline.setColor(Graphics.COLOR_BLUE);
                    polyline.setWidth(3);
                    mapView.setPolyline(polyline);
                }
            }

            // Set visible area to frame both user position and station
            if (mLocationInfo != null && mLocationInfo.position != null) {
                var uCoords = mLocationInfo.position.toDegrees();
                var minLat = (uCoords[0] < mStationLat) ? uCoords[0] : mStationLat;
                var maxLat = (uCoords[0] > mStationLat) ? uCoords[0] : mStationLat;
                var minLon = (uCoords[1] < mStationLon) ? uCoords[1] : mStationLon;
                var maxLon = (uCoords[1] > mStationLon) ? uCoords[1] : mStationLon;
                var latPad = (maxLat - minLat) * 0.3 + 0.002;
                var lonPad = (maxLon - minLon) * 0.3 + 0.002;
                var topLeft = new Position.Location(
                    {:latitude => maxLat + latPad, :longitude => minLon - lonPad, :format => :degrees}
                );
                var bottomRight = new Position.Location(
                    {:latitude => minLat - latPad, :longitude => maxLon + lonPad, :format => :degrees}
                );
                mapView.setMapVisibleArea(topLeft, bottomRight);
            }

            mapView.setMapMode(WatchUi.MAP_MODE_BROWSE);
            mMapActive = true;
            WatchUi.pushView(mapView, new TrainTimeMapDelegate(self), WatchUi.SLIDE_LEFT);
        } catch (e) {
            mMapActive = false;
            showToast("Map unavailable");
        }
    }

    function showToast(msg) {
        mToast = msg;
        mToastTick = Time.now().value();
        Haptics.vibrateShort();
        WatchUi.requestUpdate();
    }

    function exitMapView() {
        mMapActive = false;
    }

    // Single inbound entry point for everything the phone sends. Each action is
    // an optional overlay: with no phone, or an unknown action, this is a no-op
    // and the watch keeps running entirely on its own.
    function handlePhoneMessage(data) {
        if (data == null || !data.hasKey("action")) { return; }
        var action = data["action"];
        // Ack first: draining on the ack's own arrival would retransmit the very
        // reminder it clears.
        if (action.equals("ackReminder")) {
            if (ReminderQueue.ack(data.hasKey("id") ? data["id"] : null)) {
                mReminderNotified = true;
                showToast("Sent to phone");
            }
            return;
        }
        // Any other inbound message proves the phone app is listening: flush the
        // reminder outbox.
        ReminderQueue.drainIfDue(Time.now().value());
        // The phone foregrounded and wants a liveness signal now, not at the
        // next heartbeat.
        if (action.equals("ping")) {
            mLastAliveTs = Time.now().value();
            PhoneSync.sendHello();
            return;
        }
        // Favourites sync applies in any state, including while tracking, so it
        // sits ahead of the tracking guard below.
        if (action.equals("favourites")) {
            applyFavouritesFromPhone(data);
            return;
        }
        // Tracking is the end game: while tracking, the phone's navigation must
        // not pull the watch out. Only a fresh track command switches what it
        // tracks; location still flows through as a GPS fallback.
        if (mAppState == 2 && !action.equals("track") && !action.equals("loc")) { return; }
        if (action.equals("track")) {
            enterTrackingFromPhone(data);
        } else if (action.equals("mode")) {
            setModeFromPhone(data.hasKey("mode") ? data["mode"].toNumber() : null);
        } else if (action.equals("station")) {
            showStationFromPhone(data);
        } else if (action.equals("loc")) {
            onPhoneLocation(data);
        } else if (action.equals("back")) {
            // The phone left tracking. Follow it back to the station view.
            if (mAppState == 2) {
                exitToStationView();
                WatchUi.requestUpdate();
            }
        }
    }

    // Mirror a mode switch made on the phone. Switches among the nearby station
    // groups the watch already holds; if it has none for that mode (e.g. relying
    // on phone-backfilled location), pulls a fresh search.
    function setModeFromPhone(mode) {
        if (mode == null) { return; }
        var stations = getStationsForMode(mode);
        if (stations != null && stations.size() > 0) {
            mCurrentMode = mode;
            mManualStation = false;
            mStations = stations;
            mStationIndex = 0;
            selectStation(0);
        } else {
            mCurrentMode = mode;
            var pos = effectivePosition();
            if (pos != null && !mRequestInFlight) {
                mStatus = "Finding stations...";
                mRequestInFlight = true;
                mRequestStartTime = Time.now().value();
                ApiHandler.fetchStations(self, pos[0], pos[1]);
            }
        }
        WatchUi.requestUpdate();
    }

    // Mirror a station the phone picked. Reuses the quick-launch path, so the
    // station is shown exactly as a pinned station would be.
    function showStationFromPhone(data) {
        if (data == null) { return; }
        var stId = data.hasKey("stId") ? data["stId"] : null;
        if (stId == null) { return; }
        var name = data.hasKey("name") ? data["name"] : "Station";
        var lat = data.hasKey("lat") ? data["lat"] : null;
        var lon = data.hasKey("lon") ? data["lon"] : null;
        launchStation(stId, name, lat, lon);
    }

    // The phone pushed its current location. Supplemental only, recorded for use
    // when the watch's own GPS is unusable or outside Switzerland.
    function onPhoneLocation(data) {
        if (data == null) { return; }
        var lat = data.hasKey("lat") ? data["lat"] : null;
        var lon = data.hasKey("lon") ? data["lon"] : null;
        if (lat == null || lon == null) { return; }
        mPhoneLat = lat;
        mPhoneLon = lon;
        mPhoneLocTs = Time.now().value();
        // Use it straight away if our own GPS isn't giving a usable in-bounds fix.
        if (!gpsUsableInBounds()) {
            searchFromPhoneLocation();
            if (mAppState >= 2) { updateWalkDistance(); }
        }
        WatchUi.requestUpdate();
    }

    // True when the watch's own GPS is good enough AND inside Switzerland. A fix
    // like this is always preferred over the phone. The watch stays primary.
    function gpsUsableInBounds() {
        if (mLocationInfo == null || mLocationInfo.position == null) { return false; }
        if (mGpsQuality == null || mGpsQuality < Position.QUALITY_POOR) { return false; }
        var c = mLocationInfo.position.toDegrees();
        var lat = c[0];
        var lon = c[1];
        return lat >= 45.8 && lat <= 47.8 && lon >= 5.9 && lon <= 10.5;
    }

    function phoneLocFresh() {
        if (mPhoneLat == null || mPhoneLon == null || mPhoneLocTs == null) { return false; }
        return (Time.now().value() - mPhoneLocTs) < 120;
    }

    // Best-known user position: a usable in-bounds watch fix wins; else a fresh
    // phone location; else any watch fix we hold; else the last search point.
    // Never lets phone coords override a good watch fix.
    function effectivePosition() {
        if (gpsUsableInBounds()) {
            return mLocationInfo.position.toDegrees();
        }
        if (phoneLocFresh()) {
            return [ mPhoneLat, mPhoneLon ];
        }
        if (mLocationInfo != null && mLocationInfo.position != null) {
            return mLocationInfo.position.toDegrees();
        }
        if (mLastSearchLat != null && mLastSearchLon != null) {
            return [ mLastSearchLat, mLastSearchLon ];
        }
        return null;
    }

    // When the watch has no station and a fresh phone location exists, kick off a
    // nearby search from the phone's coordinates. Returns true if it handled it.
    function searchFromPhoneLocation() {
        if (!phoneLocFresh()) { return false; }
        if (mStationId != null || mManualStation || mAppState >= 2) { return false; }
        if (mRequestInFlight) { return true; }
        mStatus = "Finding stations...";
        mRequestInFlight = true;
        mRequestStartTime = Time.now().value();
        ApiHandler.fetchStations(self, mPhoneLat, mPhoneLon);
        return true;
    }

    // Ask the phone for its location when the watch GPS is weak. Throttled so a
    // run of bad fixes doesn't spam the channel.
    function requestPhoneLocation() {
        if (mLastLocRequestTs != null && (Time.now().value() - mLastLocRequestTs) < 30) {
            return;
        }
        mLastLocRequestTs = Time.now().value();
        PhoneSync.requestLocation();
    }

    function enterTrackingFromPhone(data) {
        if (data == null) { return; }
        if (!data.hasKey("action") || !data["action"].equals("track")) { return; }

        // Wake from inactive state if needed
        if (mAppState == 3) {
            mLastInteractionTime = Time.now().value();
        }

        // Set station ID for API polling
        if (data.hasKey("stId")) {
            mStationId = data["stId"];
        }

        // Build focused train from message data
        var depTs = data.hasKey("depTs") ? data["depTs"] : null;
        var minVal = 0;
        if (depTs != null) {
            minVal = (depTs - Time.now().value()) / 60;
        }

        mFocusedTrain = {
            "dest" => data.hasKey("dest") ? data["dest"] : "Unknown",
            "min" => minVal,
            "depTs" => depTs,
            "delay" => data.hasKey("delay") ? data["delay"] : 0,
            "plat" => data.hasKey("plat") ? data["plat"] : "",
            "platChg" => data.hasKey("platChg") ? data["platChg"] : false,
            "line" => data.hasKey("line") ? data["line"] : "",
            "cat" => data.hasKey("cat") ? data["cat"] : null,
            "trainNum" => data.hasKey("trainNum") ? data["trainNum"] : null,
            "opRef" => data.hasKey("opRef") ? data["opRef"] : null
        };

        mAppState = 2;
        mConsecutiveErrors = 0;
        mLastFetchTime = 0;
        maybeFetchFormation(mFocusedTrain);

        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 1000, true);
        }

        Haptics.vibrateShort();
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
            mFocusedTrain["line"] = bestMatch["line"];
            if (bestMatch["platChg"] && (oldPlat == null || !oldPlat.equals(bestMatch["plat"]))) {
                Haptics.vibrateDouble();
            }
        } else {
            // Not on the board yet: a shared route the phone pushed early, before
            // its train reaches the board. Keep the local countdown until the
            // train has actually departed, then give up.
            var depTs = mFocusedTrain["depTs"];
            if (depTs != null && Time.now().value() < depTs + 90) {
                return;
            }
            Haptics.vibrateShort();
            exitToStationView();
        }
    }

    // --- Walk calculations ---

    function getWalkMinutes() {
        if (mStationLat != null && mStationLon != null) {
            var pos = effectivePosition();
            if (pos != null) {
                var dist = GeoMath.calculateDistance(pos[0], pos[1], mStationLat, mStationLon);
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
        var pos = effectivePosition();
        if (pos == null) {
            return;
        }
        var dist = GeoMath.calculateDistance(pos[0], pos[1], mStationLat, mStationLon);
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

        // Station counter lives in the header carousel, not here
        return timeStr + " walk - " + dist + "m";
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
        mFavouriteData = null;

        // Use embedded departures if available (closest station per mode)
        if (station.hasKey("departures") && station["departures"] != null
                && station["departures"].size() > 0) {
            mTrainData = ApiHandler.parseDepartureArray(station["departures"]);
            mFavouriteData = ApiHandler.extractFavourites(mTrainData, mStationId);
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

    // --- Quick launch (pinned stations & favourite trains) ---

    // Pin/unpin the currently shown station ("My stations").
    function togglePinCurrentStation() {
        if (mStationId == null) { return; }
        MyStationsManager.toggle(mStationId, mStationName, mStationLat, mStationLon);
    }

    // Open a pinned station directly, bypassing the GPS nearby search.
    function launchStation(stationId, name, lat, lon) {
        if (stationId == null) { return; }
        mManualStation = true;
        mPendingFavTrack = null;
        mAppState = 0;
        mCursorIndex = 0;
        mScrollOffset = 0;
        mFocusedTrain = null;
        mStationId = stationId;
        mStationName = name;
        mStationLat = lat;
        mStationLon = lon;
        mStations = [ { "id" => stationId, "label" => name, "lat" => lat, "lon" => lon, "dist" => 0 } ];
        mStationIndex = 0;
        mAvailableModes = [ mCurrentMode ];
        mTrainData = null;
        mFavouriteData = null;
        mWalkInfo = "";
        if (mLocationInfo != null) { updateWalkDistance(); }
        mStatus = (name != null) ? name : "Station";
        mLastInteractionTime = Time.now().value();
        mLastFetchTime = 0;
        mRequestInFlight = true;
        mRequestStartTime = Time.now().value();
        ApiHandler.fetchDepartures(self, stationId);
        WatchUi.requestUpdate();
    }

    // Fetch a station and jump straight onto the tracking bar for a favourite
    // line+destination once the data arrives (see tryEnterPendingFavTrack).
    function enterTrackingForFavourite(stationId, name, line, dest) {
        if (stationId == null) { return; }
        mManualStation = true;
        mAppState = 0;
        mFocusedTrain = null;
        mStationId = stationId;
        mStationName = name;
        mStations = [ { "id" => stationId, "label" => name, "lat" => null, "lon" => null, "dist" => 0 } ];
        mStationIndex = 0;
        mAvailableModes = [ mCurrentMode ];
        mTrainData = null;
        mFavouriteData = null;
        mStatus = (name != null) ? name : "Station";
        mPendingFavTrack = { "line" => line, "dest" => dest };
        mLastInteractionTime = Time.now().value();
        mLastFetchTime = 0;
        mRequestInFlight = true;
        mRequestStartTime = Time.now().value();
        ApiHandler.fetchDepartures(self, stationId);
        WatchUi.requestUpdate();
    }

    // Called from the departures response when a favourite-train launch is
    // pending: match the line+dest and enter focused tracking (state 2).
    function tryEnterPendingFavTrack() {
        if (mPendingFavTrack == null || mTrainData == null) { return; }
        var line = mPendingFavTrack["line"];
        var dest = mPendingFavTrack["dest"];
        var match = null;
        for (var i = 0; i < mTrainData.size(); i++) {
            var t = mTrainData[i];
            if (t["line"] != null && t["line"].equals(line)
                    && t["dest"] != null && t["dest"].equals(dest)) {
                match = t;
                break;
            }
        }
        mPendingFavTrack = null;
        if (match == null) {
            mStatus = (mStationName != null) ? mStationName : "Station";
            return;
        }
        mFocusedTrain = {
            "dest" => match["dest"],
            "min" => match["min"],
            "depTs" => match["depTs"],
            "delay" => match["delay"],
            "plat" => match["plat"],
            "platChg" => match["platChg"],
            "line" => match["line"],
            "cat" => match["cat"],
            "trainNum" => match["trainNum"],
            "opRef" => match["opRef"]
        };
        mAppState = 2;
        mConsecutiveErrors = 0;
        mLastFetchTime = Time.now().value();
        maybeFetchFormation(match);
        if (mTimer != null) {
            mTimer.stop();
            mTimer.start(method(:onTimerTick), 1000, true);
        }
        Haptics.vibrateShort();
        PhoneSync.sendTrackStarted(mFocusedTrain, mStationId);
        ReviewPrompt.incrementTrackCount();
    }

    // --- Position & Timer ---

    function onPosition(info as Position.Info) as Void {
        // QUALITY_NOT_AVAILABLE means coordinates are garbage
        // (Fenix 6 bug: returns 0,0 instead of null)
        // QUALITY_LAST_KNOWN and above are valid (cached or live)
        if (info == null || info.position == null
                || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            if (mStationId == null && !mLoadedFromCache) {
                // No usable watch GPS, lean on the phone if it offered one,
                // else ask the phone for it.
                if (!searchFromPhoneLocation()) {
                    requestPhoneLocation();
                }
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

        // Valid position (LAST_KNOWN or better): store it
        mLocationInfo = info;

        // Update heading when moving; keep last known heading when stationary
        if (info.speed != null && info.speed > 0.5 && info.heading != null) {
            mHeading = info.heading;
        }

        // Persist location to Storage for next app launch
        Storage.setValue("lastLat", lat.toFloat());
        Storage.setValue("lastLon", lon.toFloat());

        // Switzerland bounding box check: don't clear loaded stations (border hysteresis)
        if (lat < 45.8 || lat > 47.8 || lon < 5.9 || lon > 10.5) {
            if (mStationId == null) {
                // Outside Switzerland with no station, fall back to the phone's
                // location if it has one, else ask for it.
                if (!searchFromPhoneLocation()) {
                    mStatus = "Not in Switzerland";
                    requestPhoneLocation();
                }
                WatchUi.requestUpdate();
            }
            return;
        }

        // Skip station search in tracking/inactive (still update GPS + walk distance)
        if (mAppState >= 2) {
            updateWalkDistance();
            WatchUi.requestUpdate();
            return;
        }

        // A quick-launched station is the user's explicit choice, don't let a
        // GPS re-search replace it (still keep the walk distance live).
        if (mManualStation) {
            updateWalkDistance();
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
                ApiHandler.fetchStations(self, lat, lon);
            }
            WatchUi.requestUpdate();
            return;
        }

        // Re-search stations if moved >500m from last search. The loaded stations
        // stay live until the new response is adopted, so a failed fetch never
        // strands the app with nothing to show or cycle
        if ((hasMovedSignificantly(lat, lon) || mStationId == null) && !mRequestInFlight) {
            if (mStationId == null) {
                mStatus = "Finding stations...";
            }
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

        // Liveness heartbeat to the phone every ~7s while a phone is connected. The
        // phone never pings us (that could wake a closed app), so this is how it knows
        // the app is open.
        if (System.getDeviceSettings().phoneConnected) {
            var nowSec = Time.now().value();
            if (mLastAliveTs == null || (nowSec - mLastAliveTs) >= 7) {
                mLastAliveTs = nowSec;
                PhoneSync.sendAlive();
            }
        }

        // No ack a few seconds after queuing a reminder means the phone app is
        // not listening; say so once. The outbox delivers it when the app opens.
        if (!mReminderNotified && mReminderQueuedTs != null
                && Time.now().value() - mReminderQueuedTs > 5) {
            mReminderNotified = true;
            if (ReminderQueue.hasPending()) {
                showToast("Will send when phone app opens");
            }
        }

        // Request timeout: if in-flight for >30s, force-reset
        if (mRequestInFlight && mRequestStartTime != null) {
            var elapsed = Time.now().value() - mRequestStartTime;
            if (elapsed > 30) {
                mRequestInFlight = false;
                mRequestStartTime = null;
            }
        }

        // Always poll for updated position (detects leaving Switzerland)
        // Only trust QUALITY_LAST_KNOWN or better. NOT_AVAILABLE gives garbage (0,0 or 180,180)
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
                        if (!searchFromPhoneLocation()) {
                            mStatus = "Not in Switzerland";
                            requestPhoneLocation();
                        }
                        WatchUi.requestUpdate();
                    }
                    return;
                }

                // Re-search stations if moved >500m from last search (only in
                // station/selection view). Loaded stations stay until the
                // response is adopted
                if (mAppState <= 1 && !mManualStation && !mRequestInFlight
                        && hasMovedSignificantly(lat, lon)) {
                    mRequestInFlight = true;
                    mRequestStartTime = Time.now().value();
                    ApiHandler.fetchStations(self, lat, lon);
                }
            }
        } else if (mStationId == null && mAppState <= 1 && !mManualStation) {
            // No usable watch GPS this tick. Backfill from the phone if we can.
            if (!searchFromPhoneLocation()) {
                requestPhoneLocation();
            }
        }

        // Update walk distance every tick (5s)
        updateWalkDistance();

        // Heartbeat vibration when behind schedule in tracking mode
        if (mAppState == 2 && mFocusedTrain != null) {
            var focusedMin = getFocusedMinutesUntil();
            // Departed >1 min ago: drop straight to the inactive tap-to-refresh state, not the
            // station view, so API polling stops instead of continuing every 30s.
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

        // Inactivity timeout: enter inactive if idle for 60s in station/selection view
        if ((mAppState == 0 || mAppState == 1) && Time.now().value() - mLastInteractionTime >= 60) {
            enterInactiveState();
            WatchUi.requestUpdate();
            return;
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
