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

// Review-prompt gate. Timestamps in seconds; NOW is arbitrary but fixed.
const REVIEW_NOW = 1750000000;
const REVIEW_OLD_ENOUGH = REVIEW_NOW - ReviewPrompt.MIN_AGE_SEC;

(:test)
function testReviewBelowThresholdNeverPrompts(logger) {
    return !ReviewPrompt.shouldPrompt(2, null, "0.5.0", REVIEW_OLD_ENOUGH, 0, false, REVIEW_NOW);
}

(:test)
function testReviewAtThresholdPrompts(logger) {
    return ReviewPrompt.shouldPrompt(3, null, "0.5.0", REVIEW_OLD_ENOUGH, 0, false, REVIEW_NOW);
}

(:test)
function testReviewOncePerVersion(logger) {
    return !ReviewPrompt.shouldPrompt(9, "0.5.0", "0.5.0", REVIEW_OLD_ENOUGH, 0, false, REVIEW_NOW)
        && ReviewPrompt.shouldPrompt(9, "0.4.2", "0.5.0", REVIEW_OLD_ENOUGH, 0, false, REVIEW_NOW);
}

(:test)
function testReviewYoungInstallDoesNotPrompt(logger) {
    return !ReviewPrompt.shouldPrompt(3, null, "0.5.0", REVIEW_OLD_ENOUGH + 1, 0, false, REVIEW_NOW)
        && ReviewPrompt.shouldPrompt(3, null, "0.5.0", REVIEW_OLD_ENOUGH, 0, false, REVIEW_NOW);
}

(:test)
function testReviewMissingFirstLaunchNeverPrompts(logger) {
    return !ReviewPrompt.shouldPrompt(9, null, "0.5.0", null, 0, false, REVIEW_NOW);
}

(:test)
function testReviewSnoozeWindow(logger) {
    return !ReviewPrompt.shouldPrompt(3, null, "0.5.0", REVIEW_OLD_ENOUGH, REVIEW_NOW + 1, false, REVIEW_NOW)
        && ReviewPrompt.shouldPrompt(3, null, "0.5.0", REVIEW_OLD_ENOUGH, REVIEW_NOW, false, REVIEW_NOW);
}

(:test)
function testReviewOptOutWins(logger) {
    return !ReviewPrompt.shouldPrompt(99, null, "0.5.0", REVIEW_OLD_ENOUGH, 0, true, REVIEW_NOW);
}
