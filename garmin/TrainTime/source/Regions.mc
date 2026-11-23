// The regions the app covers. One entry per region: its coverage box, the
// prefix its station ids carry and the features its data supports. The list
// matches the backend's and the phones' region registries; adding a region is
// adding one entry here. Swiss ids are bare, so Switzerland has the empty
// prefix and is the fallback for an id no other prefix matches.
module Regions {

    const SWITZERLAND = "ch";
    const MELBOURNE = "au-vic";

    const ALL = [
        {
            :id => SWITZERLAND,
            :minLat => 45.8, :maxLat => 47.8, :minLon => 5.9, :maxLon => 10.5,
            :prefix => "",
            :formation => true,
        },
        {
            :id => MELBOURNE,
            :minLat => -38.5, :maxLat => -37.4, :minLon => 144.4, :maxLon => 145.7,
            :prefix => "au-vic-",
            :formation => false,
        },
    ];

    // The region whose box holds the point, or null outside every region.
    function at(lat, lon) {
        if (lat == null || lon == null) { return null; }
        for (var i = 0; i < ALL.size(); i++) {
            var r = ALL[i];
            if (lat >= r[:minLat] && lat <= r[:maxLat] && lon >= r[:minLon] && lon <= r[:maxLon]) {
                return r;
            }
        }
        return null;
    }

    // The region a station id belongs to: the longest matching prefix, so a
    // bare id falls back to Switzerland.
    function forStationId(id) {
        var best = ALL[0];
        if (id == null) { return best; }
        var s = id.toString();
        var bestLen = 0;
        for (var i = 0; i < ALL.size(); i++) {
            var p = ALL[i][:prefix];
            var n = p.length();
            if (n > bestLen && s.length() >= n && s.substring(0, n).equals(p)) {
                best = ALL[i];
                bestLen = n;
            }
        }
        return best;
    }
}
