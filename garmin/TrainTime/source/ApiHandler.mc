using Toybox.Communications;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;

module ApiHandler {

    function fetchStations(view, lat, lon) {
        view.mLastSearchLat = lat;
        view.mLastSearchLon = lon;

        var url = "https://api.traintime.ch/v1/nearby"
            + "?lat=" + lat + "&lon=" + lon;

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
                // Name fallback for trains
                if (view.mTrainStations.size() == 0) {
                    var cityName = extractCityName(view);
                    if (cityName != null) {
                        fetchStationsByName(view, cityName);
                    }
                }
                rebuildModesAndSelect(view);
            }
        } else if (responseCode == 429) {
            view.mStatus = "Rate limited";
        } else {
            view.mStatus = "Station error: " + responseCode;
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
            result.add({
                "id" => s["id"],
                "label" => s.hasKey("name") ? s["name"] : "Station",
                "dist" => s.hasKey("dist") ? s["dist"] : 0,
                "lat" => s.hasKey("lat") ? s["lat"] : null,
                "lon" => s.hasKey("lon") ? s["lon"] : null
            });
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

            view.mRequestInFlight = true;
            view.mRequestStartTime = Time.now().value();
            fetchDepartures(view, view.mStationId);
        }
    }

    function extractCityName(view) {
        // Swiss stops follow "City, Stop Name" format
        var stations = view.mBusStations.size() > 0 ? view.mBusStations : view.mTramStations;
        if (stations.size() == 0) { return null; }
        var name = stations[0]["label"];
        var commaIdx = name.find(",");
        if (commaIdx != null && commaIdx > 0) {
            return name.substring(0, commaIdx);
        }
        return name;
    }

    function fetchStationsByName(view, cityName) {
        var url = "https://api.traintime.ch/v1/nearby"
            + "?lat=" + view.mLastSearchLat + "&lon=" + view.mLastSearchLon
            + "&query=" + cityName;

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };

        Communications.makeWebRequest(url, null, params, view.method(:onTrainStationsReceived));
    }

    function handleTrainStationsResponse(view, responseCode, data) {
        if (responseCode != 200 || data == null || !(data instanceof Lang.Dictionary)) {
            return;
        }

        view.mTrainStations = parseStationGroup(data, "train");

        if (view.mTrainStations.size() > 0) {
            // Rebuild modes to include trains
            var hadTrain = false;
            for (var i = 0; i < view.mAvailableModes.size(); i++) {
                if (view.mAvailableModes[i] == 0) { hadTrain = true; }
            }
            if (!hadTrain) {
                // Insert train at beginning so it appears first
                var newModes = [0];
                for (var i = 0; i < view.mAvailableModes.size(); i++) {
                    newModes.add(view.mAvailableModes[i]);
                }
                view.mAvailableModes = newModes;
            }
            // Only auto-switch if in station view — don't disrupt active tracking
            if (view.mAppState == 0) {
                view.mCurrentMode = 0;
                view.mStations = view.getStationsForMode(0);
                if (view.mStations != null && view.mStations.size() > 0) {
                    view.mStationIndex = 0;
                    view.selectStation(0);
                }
            }
        }
    }

    function fetchDepartures(view, stationId) {
        var url = "https://api.traintime.ch/v1/departures"
            + "?id=" + stationId
            + "&limit=10";

        var params = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => { "X-API-Key" => Secrets.API_KEY }
        };

        Communications.makeWebRequest(url, null, params, view.method(:onTrainDataReceived));
    }

    function handleDeparturesResponse(view, responseCode, data) {
        view.mRequestInFlight = false;
        view.mRequestStartTime = null;

        if (responseCode == 200 && data != null && data instanceof Lang.Dictionary && data.hasKey("departures")) {
            view.mConsecutiveErrors = 0;
            view.mTrainData = [];
            var departures = data["departures"];
            var nowSeconds = Time.now().value();

            for (var i = 0; i < departures.size() && i < 10; i++) {
                var dep = departures[i];
                var destination = (dep.hasKey("to") && dep["to"] != null) ? dep["to"] : "?";
                var category = (dep.hasKey("category") && dep["category"] != null) ? dep["category"] : "";
                var number = (dep.hasKey("number") && dep["number"] != null) ? dep["number"] : "";
                var lineNumber = "";
                if (category.equals("B") || category.equals("T") || category.equals("NFB") || category.equals("NFT") || category.equals("M")) {
                    lineNumber = number;
                }

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

                view.mTrainData.add({
                    "min" => minutesUntil,
                    "depTs" => depTs,
                    "delay" => delay,
                    "plat" => platform,
                    "platChg" => platformChanged,
                    "dest" => destination,
                    "line" => lineNumber
                });
            }

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
                // Tolerate transient errors in tracking mode
                view.mConsecutiveErrors = view.mConsecutiveErrors + 1;
                if (view.mConsecutiveErrors >= 3) {
                    view.mTrainData = null;
                    if (responseCode == 429) {
                        view.mStatus = "Rate limited";
                    } else {
                        view.mStatus = "Error: " + responseCode;
                    }
                    view.exitToStationView();
                }
            } else {
                if (responseCode == 429) {
                    view.mStatus = "Rate limited";
                } else {
                    view.mStatus = "Error: " + responseCode;
                }
                view.mTrainData = null;
                if (view.mAppState > 0) {
                    view.exitToStationView();
                }
            }
        }
        WatchUi.requestUpdate();
    }
}
