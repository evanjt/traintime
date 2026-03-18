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

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };

        Communications.makeWebRequest(url, null, params, view.method(:onTrainDataReceived));
    }

    function parseDepartureArray(departures) {
        var result = [];
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

            result.add({
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
            });
        }
        return result;
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

            if (view.mStationName != null) {
                view.mStatus = view.mStationName;
            }

            // Clamp cursor in selection mode
            if (view.mAppState == 1) {
                var total = view.mTrainData.size();
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
