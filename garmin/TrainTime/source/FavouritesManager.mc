using Toybox.Application.Storage;
using Toybox.Lang;

module FavouritesManager {

    // Storage key: "favourites" -> Dictionary { stationId => [ [lineNumber, destination, stationName], ... ] }
    // Max ~20 favourites total across all stations

    function getFavourites() {
        var favs = Storage.getValue("favourites");
        if (favs == null || !(favs instanceof Lang.Dictionary)) {
            return {};
        }
        return favs;
    }

    function saveFavourites(favs) {
        Storage.setValue("favourites", favs);
    }

    function getFavouritesForStation(stationId) {
        var favs = getFavourites();
        if (favs.hasKey(stationId)) {
            var arr = favs[stationId];
            if (arr != null && arr instanceof Lang.Array) {
                return arr;
            }
        }
        return [];
    }

    function isFavourite(stationId, lineNumber, destination) {
        var stationFavs = getFavouritesForStation(stationId);
        for (var i = 0; i < stationFavs.size(); i++) {
            var entry = stationFavs[i];
            if (entry[0].equals(lineNumber) && entry[1].equals(destination)) {
                return true;
            }
        }
        return false;
    }

    function addFavourite(stationId, lineNumber, destination, stationName) {
        if (isFavourite(stationId, lineNumber, destination)) {
            return;
        }
        // Check total count
        if (getTotalCount() >= 20) {
            return;
        }
        var favs = getFavourites();
        var stationFavs = [];
        if (favs.hasKey(stationId)) {
            var existing = favs[stationId];
            if (existing != null && existing instanceof Lang.Array) {
                stationFavs = existing;
            }
        }
        stationFavs.add([lineNumber, destination, stationName]);
        favs[stationId] = stationFavs;
        saveFavourites(favs);
    }

    function removeFavourite(stationId, lineNumber, destination) {
        var favs = getFavourites();
        if (!favs.hasKey(stationId)) { return; }
        var stationFavs = favs[stationId];
        if (stationFavs == null || !(stationFavs instanceof Lang.Array)) { return; }

        var newFavs = [];
        for (var i = 0; i < stationFavs.size(); i++) {
            var entry = stationFavs[i];
            if (!(entry[0].equals(lineNumber) && entry[1].equals(destination))) {
                newFavs.add(entry);
            }
        }
        if (newFavs.size() == 0) {
            favs.remove(stationId);
        } else {
            favs[stationId] = newFavs;
        }
        saveFavourites(favs);
    }

    function toggleFavourite(stationId, lineNumber, destination, stationName) {
        if (isFavourite(stationId, lineNumber, destination)) {
            removeFavourite(stationId, lineNumber, destination);
        } else {
            addFavourite(stationId, lineNumber, destination, stationName);
        }
    }

    function getTotalCount() {
        var favs = getFavourites();
        var count = 0;
        var keys = favs.keys();
        for (var i = 0; i < keys.size(); i++) {
            var arr = favs[keys[i]];
            if (arr != null && arr instanceof Lang.Array) {
                count = count + arr.size();
            }
        }
        return count;
    }

    function clearAll() {
        Storage.deleteValue("favourites");
    }

    // Build URL query param: "IC8:Brig,IR90:Visp"
    function buildFavouritesParam(stationId) {
        var stationFavs = getFavouritesForStation(stationId);
        if (stationFavs.size() == 0) {
            return null;
        }
        var parts = "";
        for (var i = 0; i < stationFavs.size(); i++) {
            if (i > 0) { parts = parts + ","; }
            parts = parts + stationFavs[i][0] + ":" + stationFavs[i][1];
        }
        return parts;
    }

    // Favourites as an array of {stId,line,dest,name} dicts for phone sync. The
    // cross-platform wire shape both phone companions parse and build.
    function getFavouritesForSync() {
        var all = getAllFavourites();  // [line, dest, name, stId]
        var result = [];
        for (var i = 0; i < all.size(); i++) {
            var e = all[i];
            result.add({ "stId" => e[3], "line" => e[0], "dest" => e[1], "name" => e[2] });
        }
        return result;
    }

    // Outer-join an incoming favourites array (of {stId,line,dest,name}) into
    // storage: add any the watch lacks, never remove (matching the phone's union).
    // Returns true if the local set grew. Deliberately does NOT re-broadcast: each
    // side pushes on its own change and the phone re-seeds on watch-open, which
    // converges additions without an apply-triggered loop.
    function applyUnionFromSync(incoming) {
        if (incoming == null || !(incoming instanceof Lang.Array)) { return false; }
        var before = getTotalCount();
        for (var i = 0; i < incoming.size(); i++) {
            var e = incoming[i];
            if (e instanceof Lang.Dictionary) {
                var stId = e["stId"];
                var line = e["line"];
                var dest = e["dest"];
                var name = e["name"] != null ? e["name"] : stId;
                if (stId != null && line != null && dest != null) {
                    addFavourite(stId, line, dest, name);
                }
            }
        }
        return getTotalCount() != before;
    }

    // Get all favourites as flat array of [lineNumber, destination, stationName, stationId]
    function getAllFavourites() {
        var favs = getFavourites();
        var result = [];
        var keys = favs.keys();
        for (var i = 0; i < keys.size(); i++) {
            var stId = keys[i];
            var arr = favs[stId];
            if (arr != null && arr instanceof Lang.Array) {
                for (var j = 0; j < arr.size(); j++) {
                    var entry = arr[j];
                    var stName = (entry.size() > 2) ? entry[2] : stId;
                    result.add([entry[0], entry[1], stName, stId]);
                }
            }
        }
        return result;
    }
}
