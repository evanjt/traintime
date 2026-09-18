using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Timer;
using Toybox.WatchUi;
using Toybox.Application;
using Toybox.Application.Storage;

// One attempt of an API request: the host it went to and when it left. The
// object is the makeWebRequest callback, so a reply from a cancelled or
// superseded attempt is told apart by identity, whatever code it carries.
class ApiAttempt {
    var view;
    var kind;
    var path;
    var hosts;
    var hostIdx;
    var attempt;
    var startTs;

    function initialize(v, k, p, h, firstHost) {
        view = v;
        kind = k;
        path = p;
        hosts = h;
        hostIdx = firstHost;
        attempt = 0;
        startTs = null;
    }

    function url() {
        return ApiHandler.urlFor(hosts, hostIdx, path);
    }

    function isLast() {
        return attempt >= hosts.size() - 1;
    }

    function advance() {
        attempt = attempt + 1;
        hostIdx = (hostIdx + 1) % hosts.size();
    }

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        ApiHandler.onResponse(self, responseCode, data);
    }
}

// The view's own timer ticks at 5 s on the board, too coarse for a 5 s
// attempt limit, so the timed request slot runs its own 1 s ticker.
class ApiTicker {
    var mTimer;

    function initialize() {
        mTimer = new Timer.Timer();
    }

    function start() {
        mTimer.stop();
        mTimer.start(method(:onTick), 1000, true);
    }

    function stop() {
        mTimer.stop();
    }

    function onTick() as Void {
        ApiHandler.tick(Time.now().value());
    }
}

module ApiHandler {

    // Failover order (Q9). api is the name a load balancer could later sit on,
    // the other two are the cluster tunnel and the Worker alias.
    const HOSTS = ["https://api.traintime.ch", "https://api1.traintime.ch", "https://api2.traintime.ch"];
    const DEFAULT_HOST = "https://api.traintime.ch";

    // Per-attempt budget (Q10): 5 s on every host but the last, 10 s on the
    // last, so three attempts still fit inside the view's 30 s guard. Connect
    // IQ has no request timeout option, so the ticker enforces it with
    // cancelAllRequests. A failed primary is left alone for five minutes.
    const ATTEMPT_SECS = 5;
    const LAST_ATTEMPT_SECS = 10;
    const PRIMARY_REPROBE_SECS = 300;

    const KIND_STATIONS = 0;
    const KIND_DEPARTURES = 1;
    const KIND_FORMATION = 2;

    var mActiveHost = 0;
    var mPrimaryFailedAt = null;
    // Stations and departures share one timed slot: the view never has both in
    // flight. Formation runs beside it and is only retried on a failed reply.
    var mPending = null;
    var mPendingFormation = null;
    var mTicker = null;

    // The Connect IQ app setting "apiHost", read once per request. Empty or
    // anything that is not an https URL falls back to the built-in host list,
    // so a typo in Garmin Connect never strands the watch on a dead host. A
    // custom host is a single-host list: no failover.
    function hosts() {
        var raw = null;
        if (Application has :Properties) {
            try {
                raw = Application.Properties.getValue("apiHost");
            } catch (e) {
                raw = null;
            }
        }
        return hostsFor(raw);
    }

    function hostsFor(raw) {
        var host = hostOrDefault(raw);
        if (host.equals(DEFAULT_HOST)) { return HOSTS; }
        return [host];
    }

    function hostOrDefault(raw) {
        if (!(raw instanceof Lang.String)) { return DEFAULT_HOST; }
        var host = trim(raw);
        if (host.length() <= 8 || !host.substring(0, 8).equals("https://")) {
            return DEFAULT_HOST;
        }
        while (host.length() > 8 && host.substring(host.length() - 1, host.length()).equals("/")) {
            host = host.substring(0, host.length() - 1);
        }
        if (host.length() <= 8) { return DEFAULT_HOST; }
        return host;
    }

    function trim(s) {
        var start = 0;
        var end = s.length();
        while (start < end && s.substring(start, start + 1).equals(" ")) { start++; }
        while (end > start && s.substring(end - 1, end).equals(" ")) { end--; }
        return s.substring(start, end);
    }

    function urlFor(hostList, idx, path) {
        return hostList[idx] + path;
    }

    // Host bookkeeping. A failure moves the next attempt one host along; a
    // failed primary is skipped until the re-probe window passes.
    function preferredHost(now) {
        if (mPrimaryFailedAt != null && now - mPrimaryFailedAt < PRIMARY_REPROBE_SECS) {
            return mActiveHost;
        }
        return 0;
    }

    function recordHostFailure(idx, now) {
        if (idx == 0) { mPrimaryFailedAt = now; }
        mActiveHost = (idx + 1) % HOSTS.size();
    }

    function recordHostSuccess(idx) {
        mActiveHost = idx;
        if (idx == 0) { mPrimaryFailedAt = null; }
    }

    function resetHostState() {
        mActiveHost = 0;
        mPrimaryFailedAt = null;
    }

    // Fail over on what a dead host produces: 5xx, 429, a non-JSON body (-400,
    // how Cloudflare's own error pages arrive, per I6), a timed-out or dropped
    // request and the BLE transport errors. Never on our own 4xx, on a cancel,
    // on a missing phone or on a body the watch cannot hold.
    function shouldFailover(code) {
        if (code >= 500 || code == 429) { return true; }
        if (code == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) { return true; }
        if (code == Communications.NETWORK_REQUEST_TIMED_OUT) { return true; }
        if (code == Communications.REQUEST_CONNECTION_DROPPED) { return true; }
        return code >= Communications.BLE_SERVER_TIMEOUT && code <= Communications.BLE_ERROR;
    }

    function request(view, kind, path) {
        var now = Time.now().value();
        var hostList = hosts();
        var first = hostList.size() > 1 ? preferredHost(now) : 0;
        var a = new ApiAttempt(view, kind, path, hostList, first);
        if (kind == KIND_FORMATION) {
            mPendingFormation = a;
        } else {
            mPending = a;
            if (mTicker == null) { mTicker = new ApiTicker(); }
            mTicker.start();
        }
        send(a);
    }

    function send(a) {
        a.startTs = Time.now().value();
        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };
        Communications.makeWebRequest(a.url(), null, params, a.method(:onResponse));
    }

    function clearPending(a) {
        if (a == mPending) {
            mPending = null;
            if (mTicker != null) { mTicker.stop(); }
        } else if (a == mPendingFormation) {
            mPendingFormation = null;
        }
    }

    function failover(a, now) {
        if (a.hosts.size() > 1) { recordHostFailure(a.hostIdx, now); }
        a.advance();
        System.println("failover -> " + a.hosts[a.hostIdx]);
        if (a != mPendingFormation) { a.view.mRequestStartTime = now; }
        send(a);
    }

    function onResponse(a, responseCode, data) {
        if (a != mPending && a != mPendingFormation) { return; }
        var now = Time.now().value();
        if (responseCode == 200) {
            if (a.hosts.size() > 1) { recordHostSuccess(a.hostIdx); }
        } else if (shouldFailover(responseCode)) {
            if (!a.isLast()) {
                failover(a, now);
                return;
            }
            if (a.hosts.size() > 1) { recordHostFailure(a.hostIdx, now); }
        }
        clearPending(a);
        dispatch(a, responseCode, data);
    }

    // Enforces the per-attempt budget on the timed slot. A cancel also drops a
    // formation request in flight; its reply is a cancel code, never a failover.
    function tick(now) {
        var a = mPending;
        if (a == null || a.startTs == null) { return; }
        var limit = a.isLast() ? LAST_ATTEMPT_SECS : ATTEMPT_SECS;
        if (now - a.startTs < limit) { return; }
        Communications.cancelAllRequests();
        if (!a.isLast()) {
            failover(a, now);
            return;
        }
        if (a.hosts.size() > 1) { recordHostFailure(a.hostIdx, now); }
        clearPending(a);
        dispatch(a, Communications.NETWORK_REQUEST_TIMED_OUT, null);
    }

    function dispatch(a, responseCode, data) {
        if (a.kind == KIND_STATIONS) {
            handleStationsResponse(a.view, responseCode, data);
        } else if (a.kind == KIND_DEPARTURES) {
            handleDeparturesResponse(a.view, responseCode, data);
        } else {
            handleFormationResponse(a.view, responseCode, data);
        }
    }

    function decodeError(responseCode) {
        if (responseCode == 429) { return Txt.t(Rez.Strings.RateLimited); }
        if (responseCode == 401) { return Txt.t(Rez.Strings.UpdateRequired); }
        if (responseCode == 500) { return Txt.t(Rez.Strings.ServerError); }
        if (responseCode == -104 || responseCode == -300) { return Txt.t(Rez.Strings.TimeoutError); }
        if (responseCode == -400) { return Txt.t(Rez.Strings.NoConnection); }
        if (responseCode < 0) { return Txt.t(Rez.Strings.ConnectionError); }
        return Lang.format(Txt.t(Rez.Strings.ErrorFmt), [responseCode]);
    }

    function fetchStations(view, lat, lon) {
        view.mLastSearchLat = lat;
        view.mLastSearchLon = lon;

        var defaultMode = Storage.getValue("defaultMode");
        var modeParam = "";
        if (defaultMode == 1) { modeParam = "&mode=bus"; }
        else if (defaultMode == 2) { modeParam = "&mode=tram"; }

        var path = "/v1/nearby?lat=" + lat + "&lon=" + lon + modeParam;
        request(view, KIND_STATIONS, path);
    }

    function handleStationsResponse(view, responseCode, data) {
        view.mRequestInFlight = false;
        view.mRequestStartTime = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary) {
            var trains = parseStationGroup(data, "train");
            var buses = parseStationGroup(data, "bus");
            var trams = parseStationGroup(data, "tram");
            var specials = parseStationGroup(data, "special");

            if (trains.size() == 0 && buses.size() == 0
                    && trams.size() == 0 && specials.size() == 0) {
                view.clearStationState();
                view.mStatus = Txt.t(Rez.Strings.NoStationsNearby);
                view.mTrainData = null;
            } else {
                view.resetForNewStations();
                view.mTrainStations = trains;
                view.mBusStations = buses;
                view.mTramStations = trams;
                view.mSpecialStations = specials;
                rebuildModesAndSelect(view);
            }
        } else {
            // A failed re-search keeps the loaded stations; only a first search
            // with nothing on screen surfaces the error state
            view.mStatus = decodeError(responseCode);
            if (view.mStationId == null) {
                view.mTrainData = null;
            }
        }
        WatchUi.requestUpdate();
    }

    function parseStationGroup(data, key) {
        var result = [];
        if (!data.hasKey(key)) { return result; }
        var arr = data[key];
        if (arr == null) { return result; }
        for (var i = 0; i < arr.size(); i++) {
            var s = arr[i];
            if (!s.hasKey("id") || s["id"] == null) { continue; }
            var station = {
                "id" => s["id"],
                "label" => s.hasKey("name") ? s["name"] : "Station",
                "dist" => s.hasKey("dist") ? s["dist"] : 0,
                "lat" => s.hasKey("lat") ? s["lat"] : null,
                "lon" => s.hasKey("lon") ? s["lon"] : null
            };
            // Embed departures for closest station (first entry per mode)
            if (result.size() == 0 && s.hasKey("departures") && s["departures"] != null) {
                station["departures"] = s["departures"];
            }
            result.add(station);
        }
        return result;
    }

    function rebuildModesAndSelect(view) {
        // Bubble pinned "My stations" to the front of each mode list so the
        // default shown station (index 0) becomes the pinned one when present.
        view.mTrainStations = MyStationsManager.reorderStations(view.mTrainStations);
        view.mBusStations = MyStationsManager.reorderStations(view.mBusStations);
        view.mTramStations = MyStationsManager.reorderStations(view.mTramStations);
        view.mSpecialStations = MyStationsManager.reorderStations(view.mSpecialStations);

        // Build available modes from non-empty categories
        view.mAvailableModes = [];
        if (view.mTrainStations.size() > 0) { view.mAvailableModes.add(0); }
        if (view.mBusStations.size() > 0) { view.mAvailableModes.add(1); }
        if (view.mTramStations.size() > 0) { view.mAvailableModes.add(2); }
        if (view.mSpecialStations != null && view.mSpecialStations.size() > 0) { view.mAvailableModes.add(3); }

        // If current mode has no stations, switch to first available
        var currentStations = view.getStationsForMode(view.mCurrentMode);
        if (currentStations == null || currentStations.size() == 0) {
            if (view.mAvailableModes.size() > 0) {
                view.mCurrentMode = view.mAvailableModes[0];
            }
        }

        view.mStations = view.getStationsForMode(view.mCurrentMode);

        if (view.mStations != null && view.mStations.size() > 0) {
            view.mStationIndex = 0;
            var station = view.mStations[0];
            view.mStationId = station["id"];
            view.mStationName = station.hasKey("label") ? station["label"] : "Station";
            view.mStationLat = station.hasKey("lat") ? station["lat"] : null;
            view.mStationLon = station.hasKey("lon") ? station["lon"] : null;
            var distance = station.hasKey("dist") ? station["dist"] : 0;
            view.mWalkInfo = view.formatWalkInfo(distance);
            view.mStatus = view.mStationName;
            WatchUi.requestUpdate();

            // Use embedded departures if available (closest station per mode)
            if (station.hasKey("departures") && station["departures"] != null
                    && station["departures"].size() > 0) {
                view.mTrainData = parseDepartureArray(station["departures"]);
                view.mFavouriteData = extractFavourites(view.mTrainData, view.mStationId);
                view.mLastFetchTime = Time.now().value();
                view.mRequestInFlight = false;
                view.mRequestStartTime = null;
            } else {
                view.mRequestInFlight = true;
                view.mRequestStartTime = Time.now().value();
                fetchDepartures(view, view.mStationId);
            }
        }
    }

    function fetchDepartures(view, stationId) {
        var path = "/v1/departures?id=" + stationId + "&limit=20";

        var favParam = FavouritesManager.buildFavouritesParam(stationId);
        if (favParam != null) {
            path = path + "&favourites=" + favParam;
        }
        request(view, KIND_DEPARTURES, path);
    }

    function parseDepartureArray(departures) {
        var result = [];
        var seen = {};
        var nowSeconds = Time.now().value();

        for (var i = 0; i < departures.size() && i < 20; i++) {
            var dep = departures[i];
            var destination = (dep.hasKey("to") && dep["to"] != null) ? dep["to"] : "?";
            var category = (dep.hasKey("category") && dep["category"] != null) ? dep["category"] : "";
            var number = (dep.hasKey("number") && dep["number"] != null) ? dep["number"] : "";
            var lineNumber = number;

            var platform = (dep.hasKey("platform") && dep["platform"] != null) ? dep["platform"].toString() : "";
            var platformChanged = (dep.hasKey("platformChanged") && dep["platformChanged"] != null) ? dep["platformChanged"] : false;

            var minutesUntil = -1;
            var depTs = null;
            if (dep.hasKey("departure") && dep["departure"] != null) {
                depTs = dep["departure"];
                minutesUntil = (depTs - nowSeconds) / 60;
            }

            var delay = 0;
            if (dep.hasKey("delay") && dep["delay"] != null && dep["delay"] > 0) {
                delay = dep["delay"];
            }

            var trainNumber = (dep.hasKey("trainNumber") && dep["trainNumber"] != null) ? dep["trainNumber"].toString() : null;
            var operatorRef = (dep.hasKey("operatorRef") && dep["operatorRef"] != null) ? dep["operatorRef"].toString() : null;

            var entry = {
                "min" => minutesUntil,
                "depTs" => depTs,
                "delay" => delay,
                "plat" => platform,
                "platChg" => platformChanged,
                "dest" => destination,
                "line" => lineNumber,
                "cat" => category,
                "trainNum" => trainNumber,
                "opRef" => operatorRef
            };

            // OJP can publish the same physical train twice under twin train
            // numbers (e.g. 23153/93153). Same time, line, destination and
            // platform means the same train: keep the twin carrying the delay,
            // in the first-seen slot. Mirrors the iOS/Android dedupe.
            var key = (depTs == null ? "0" : depTs.toString())
                + "|" + lineNumber + "|" + destination + "|" + platform;
            if (seen.hasKey(key)) {
                var idx = seen[key];
                if (delay > result[idx]["delay"]) {
                    result[idx] = entry;
                }
            } else {
                seen[key] = result.size();
                result.add(entry);
            }
        }
        return result;
    }

    // Extract favourite departures from a departure list, client-side.
    // Returns first match per stored favourite, sorted by departure time.
    function extractFavourites(trainData, stationId) {
        if (stationId == null || trainData == null || trainData.size() == 0) {
            return null;
        }
        var stationFavs = FavouritesManager.getFavouritesForStation(stationId);
        if (stationFavs.size() == 0) {
            return null;
        }
        var result = [];
        for (var f = 0; f < stationFavs.size(); f++) {
            var favLine = stationFavs[f][0];
            var favDest = stationFavs[f][1];
            for (var i = 0; i < trainData.size(); i++) {
                var t = trainData[i];
                if (t["line"] != null && t["line"].equals(favLine)
                        && t["dest"] != null && t["dest"].equals(favDest)) {
                    result.add(t);
                    break;  // first match only
                }
            }
        }
        if (result.size() == 0) {
            return null;
        }
        // Sort by departure time
        for (var i = 0; i < result.size() - 1; i++) {
            for (var j = i + 1; j < result.size(); j++) {
                var a = result[i]["depTs"];
                var b = result[j]["depTs"];
                if (a != null && b != null && a > b) {
                    var tmp = result[i];
                    result[i] = result[j];
                    result[j] = tmp;
                }
            }
        }
        return result;
    }

    // Ensure favourite departures appear in the regular list so they repeat in time order.
    // Client-side extraction already pulls favourites from trainData; this covers a server
    // that returns favourites as a separate array without keeping them in "departures".
    function mergeFavourites(trainData, favData) {
        if (favData == null || favData.size() == 0) {
            return trainData;
        }
        if (trainData == null) {
            trainData = [];
        }
        for (var f = 0; f < favData.size(); f++) {
            var fav = favData[f];
            var present = false;
            for (var i = 0; i < trainData.size(); i++) {
                var t = trainData[i];
                if (t["line"] != null && t["line"].equals(fav["line"])
                        && t["dest"] != null && t["dest"].equals(fav["dest"])
                        && t["depTs"] == fav["depTs"]) {
                    present = true;
                    break;
                }
            }
            if (!present) {
                trainData.add(fav);
            }
        }
        // Sort by departure time
        for (var i = 0; i < trainData.size() - 1; i++) {
            for (var j = i + 1; j < trainData.size(); j++) {
                var a = trainData[i]["depTs"];
                var b = trainData[j]["depTs"];
                if (a != null && b != null && a > b) {
                    var tmp = trainData[i];
                    trainData[i] = trainData[j];
                    trainData[j] = tmp;
                }
            }
        }
        return trainData;
    }

    function fetchFormation(view, trainNumber, stationId, operatorRef) {
        // Format today's date as YYYY-MM-DD
        var now = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var date = now.year + "-" + now.month.format("%02d") + "-" + now.day.format("%02d");

        var path = "/v1/formation?train=" + trainNumber
            + "&date=" + date
            + "&stop=" + stationId;
        if (operatorRef != null) {
            path = path + "&operatorRef=" + operatorRef;
        }
        request(view, KIND_FORMATION, path);
    }

    function handleFormationResponse(view, responseCode, data) {
        if (responseCode != 200 || data == null || !(data instanceof Lang.Dictionary) || !data.hasKey("wagons")) {
            view.mFormationClasses = null;
            view.mFormationNumbers = null;
            view.mFormationSectors = null;
            WatchUi.requestUpdate();
            return;
        }

        var wagons = data["wagons"];
        if (wagons == null || wagons.size() == 0) {
            view.mFormationClasses = null;
            view.mFormationNumbers = null;
            view.mFormationSectors = null;
            WatchUi.requestUpdate();
            return;
        }

        var classes = new [wagons.size()];
        var numbers = new [wagons.size()];
        var sectors = new [wagons.size()];
        for (var i = 0; i < wagons.size(); i++) {
            var w = wagons[i];
            classes[i] = w.hasKey("class") ? w["class"] : 2;
            numbers[i] = (w.hasKey("number") && w["number"] != null) ? w["number"] : 0;
            sectors[i] = (w.hasKey("sector") && w["sector"] != null) ? w["sector"] : "";
        }

        view.mFormationClasses = classes;
        view.mFormationNumbers = numbers;
        view.mFormationSectors = sectors;
        WatchUi.requestUpdate();
    }

    function handleDeparturesResponse(view, responseCode, data) {
        view.mRequestInFlight = false;
        view.mRequestStartTime = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary && data.hasKey("departures")) {
            view.mConsecutiveErrors = 0;
            view.mTrainData = parseDepartureArray(data["departures"]);

            // Use server-side favourites if present, fall back to client-side extraction
            if (data.hasKey("favourites") && data["favourites"] != null
                    && data["favourites"] instanceof Lang.Array && data["favourites"].size() > 0) {
                view.mFavouriteData = parseDepartureArray(data["favourites"]);
                view.mTrainData = mergeFavourites(view.mTrainData, view.mFavouriteData);
            } else {
                view.mFavouriteData = extractFavourites(view.mTrainData, view.mStationId);
            }

            if (view.mStationName != null) {
                view.mStatus = view.mStationName;
            }

            // Quick-launch a favourite train: match line+dest in the fresh data
            // and jump straight onto the tracking bar.
            if (view.mPendingFavTrack != null) {
                view.tryEnterPendingFavTrack();
            }

            // Clamp cursor in selection mode (combined: favourites + regular)
            if (view.mAppState == 1) {
                var total = view.getSelectableCount();
                if (total == 0) {
                    view.exitToStationView();
                } else if (view.mCursorIndex >= total) {
                    view.mCursorIndex = total - 1;
                }
                // Clamp scroll offset
                if (view.mScrollOffset > total - view.mMaxVisibleTrains) {
                    view.mScrollOffset = total - view.mMaxVisibleTrains;
                    if (view.mScrollOffset < 0) { view.mScrollOffset = 0; }
                }
            }

            // Update focused train in tracking mode
            view.updateFocusedTrain();
        } else {
            if (view.mAppState == 2) {
                // In tracking mode: keep existing data, continue countdown
                // Delay/platform won't update but depTs-based countdown still works
                view.mConsecutiveErrors = view.mConsecutiveErrors + 1;
            } else {
                view.mStatus = decodeError(responseCode);
                view.mTrainData = null;
                if (view.mAppState > 0) {
                    view.exitToStationView();
                }
            }
        }
        WatchUi.requestUpdate();
    }
}
