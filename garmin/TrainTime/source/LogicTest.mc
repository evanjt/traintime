using Toybox.Test;
using Toybox.Application.Storage;

// Geo, parsing and favourites logic. Built only with `monkeyc -t`.

(:test)
function testDistanceBetweenRealStations(logger) {
    // Place de la Planta -> Gare de Sion, ~376 m by the flat-earth model.
    var d = GeoMath.calculateDistance(46.2306, 7.3576, 46.2275, 7.3596);
    return d >= 375 && d <= 377;
}

(:test)
function testDistanceIsZeroAtSamePoint(logger) {
    return GeoMath.calculateDistance(46.23, 7.36, 46.23, 7.36) == 0;
}

(:test)
function testBearingPointsNorth(logger) {
    var b = GeoMath.calculateBearing(46.0, 6.0, 47.0, 6.0);
    return b > -0.01 && b < 0.01;
}

(:test)
function testParseStationGroup(logger) {
    var data = {
        "train" => [
            { "id" => "8501120", "name" => "Lausanne", "lat" => 46.516, "lon" => 6.629, "dist" => 250 },
        ],
    };
    var stations = ApiHandler.parseStationGroup(data, "train");
    if (stations.size() != 1) { return false; }
    var s = stations[0];
    return s["id"].equals("8501120") && s["label"].equals("Lausanne") && s["dist"] == 250;
}

(:test)
function testParseDepartureArray(logger) {
    var deps = [
        { "to" => "Brig", "category" => "IC", "number" => "IC8", "departure" => 1718000600, "delay" => 2, "platform" => "3" },
    ];
    var parsed = ApiHandler.parseDepartureArray(deps);
    if (parsed.size() != 1) { return false; }
    var d = parsed[0];
    return d["dest"].equals("Brig") && d["line"].equals("IC8") && d["depTs"] == 1718000600 && d["delay"] == 2;
}

(:test)
function testBuildFavouritesParam(logger) {
    Storage.deleteValue("favourites");
    FavouritesManager.addFavourite("8501120", "IC8", "Brig", "Lausanne");
    var param = FavouritesManager.buildFavouritesParam("8501120");
    Storage.deleteValue("favourites");
    return param != null && param.equals("IC8:Brig");
}
