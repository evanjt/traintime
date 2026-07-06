using Toybox.Communications;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Application.Storage;

module ApiHandler {

    function decodeError(responseCode) {
        if (responseCode == 429) { return "Rate limited"; }
        if (responseCode == 500) { return "Server error"; }
        if (responseCode == -104) { return "Timeout"; }
        if (responseCode == -400) { return "No connection"; }
        if (responseCode < 0) { return "Connection error"; }
        return "Error: " + responseCode;
    }

    function fetchStations(view, lat, lon) {
        view.mLastSearchLat = lat;
        view.mLastSearchLon = lon;

        var defaultMode = Storage.getValue("defaultMode");
        var modeParam = "";
        if (defaultMode == 1) { modeParam = "&mode=bus"; }
        else if (defaultMode == 2) { modeParam = "&mode=tram"; }

        var url = "https://api.traintime.ch/v1/nearby"
            + "?lat=" + lat + "&lon=" + lon + modeParam;

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };

        Communications.makeWebRequest(url, null, params, view.method(:onStationsReceived));
    }

    function handleStationsResponse(view, responseCode, data) {
        view.mRequestInFlight = false;
        view.mRequestStartTime = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary) {
            view.mTrainStations = parseStationGroup(data, "train");
            view.mBusStations = parseStationGroup(data, "bus");
            view.mTramStations = parseStationGroup(data, "tram");
            view.mSpecialStations = parseStationGroup(data, "special");

            if (view.mTrainStations.size() == 0 && view.mBusStations.size() == 0
                    && view.mTramStations.size() == 0 && view.mSpecialStations.size() == 0) {
                view.mStatus = "No stations nearby";
                view.mTrainData = null;
            } else {
                rebuildModesAndSelect(view);
            }
        } else {
            view.mStatus = decodeError(responseCode);
            view.mTrainData = null;
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
        var url = "https://api.traintime.ch/v1/departures"
            + "?id=" + stationId
            + "&limit=20";

        var favParam = FavouritesManager.buildFavouritesParam(stationId);
        if (favParam != null) {
            url = url + "&favourites=" + favParam;
        }

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };

        Communications.makeWebRequest(url, null, params, view.method(:onTrainDataReceived));
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

        var url = "https://api.traintime.ch/v1/formation"
            + "?train=" + trainNumber
            + "&date=" + date
            + "&stop=" + stationId;
        if (operatorRef != null) {
            url = url + "&operatorRef=" + operatorRef;
        }

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };

        Communications.makeWebRequest(url, null, params, view.method(:onFormationReceived));
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
