using Toybox.Application.Storage;
using Toybox.Lang;

module MyStationsManager {

    // Storage key: "myStations" -> Array of { "id"=>, "name"=>, "lat"=>, "lon"=> }
    // Pinned stations bubble to the front of the nearby list (and become the
    // default shown station) and feed the glance's nearest-station tile.
    // Max 10. Mirrors FavouritesManager's storage pattern.

    function getMyStations() {
        var v = Storage.getValue("myStations");
        if (v == null || !(v instanceof Lang.Array)) {
            return [];
        }
        return v;
    }

    function save(arr) {
        Storage.setValue("myStations", arr);
    }

    function isPinned(stationId) {
        if (stationId == null) { return false; }
        var arr = getMyStations();
        for (var i = 0; i < arr.size(); i++) {
            var id = arr[i]["id"];
            if (id != null && id.equals(stationId)) {
                return true;
            }
        }
        return false;
    }

    function add(stationId, name, lat, lon) {
        if (stationId == null || isPinned(stationId)) { return; }
        var arr = getMyStations();
        if (arr.size() >= 10) { return; }
        arr.add({ "id" => stationId, "name" => name, "lat" => lat, "lon" => lon });
        save(arr);
    }

    function remove(stationId) {
        var arr = getMyStations();
        var out = [];
        for (var i = 0; i < arr.size(); i++) {
            var id = arr[i]["id"];
            if (!(id != null && id.equals(stationId))) {
                out.add(arr[i]);
            }
        }
        if (out.size() == 0) {
            Storage.deleteValue("myStations");
        } else {
            save(out);
        }
    }

    function toggle(stationId, name, lat, lon) {
        if (isPinned(stationId)) {
            remove(stationId);
        } else {
            add(stationId, name, lat, lon);
        }
    }

    function getCount() {
        return getMyStations().size();
    }

    // Reorder a station-dict array (each has "id") so pinned stations come first,
    // preserving the API's distance order within each group. Pure; null-safe.
    function reorderStations(stations) {
        if (stations == null || stations.size() == 0 || getCount() == 0) {
            return stations;
        }
        var pinned = [];
        var rest = [];
        for (var i = 0; i < stations.size(); i++) {
            var s = stations[i];
            if (s != null && s.hasKey("id") && isPinned(s["id"])) {
                pinned.add(s);
            } else {
                rest.add(s);
            }
        }
        if (pinned.size() == 0) { return stations; }
        var out = [];
        for (var i = 0; i < pinned.size(); i++) { out.add(pinned[i]); }
        for (var i = 0; i < rest.size(); i++) { out.add(rest[i]); }
        return out;
    }
}
