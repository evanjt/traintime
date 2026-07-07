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

// OJP publishes some trains twice under twin train numbers (e.g. 23153/93153).
// parseDepartureArray collapses them, keeping the twin carrying the delay in
// the first-seen slot.
(:test)
function testDedupeCollapsesTwinsKeepingDelay(logger) {
    var planned = { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718000600, "delay" => 0, "platform" => "2", "trainNumber" => "23153" };
    var delayed = { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718000600, "delay" => 1, "platform" => "2", "trainNumber" => "93153" };
    var a = ApiHandler.parseDepartureArray([planned, delayed]);
    var b = ApiHandler.parseDepartureArray([delayed, planned]);
    return a.size() == 1 && b.size() == 1
        && a[0]["trainNum"].equals("93153") && a[0]["delay"] == 1
        && b[0]["trainNum"].equals("93153") && b[0]["delay"] == 1;
}

(:test)
function testDedupeKeepsDistinguishableRows(logger) {
    var deps = [
        { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718000600, "delay" => 0, "platform" => "1" },
        { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718000600, "delay" => 0, "platform" => "2" },
        { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718001200, "delay" => 0, "platform" => "1" },
    ];
    return ApiHandler.parseDepartureArray(deps).size() == 3;
}

(:test)
function testDedupePreservesOrder(logger) {
    var deps = [
        { "to" => "Brig", "category" => "IC", "number" => "IC8", "departure" => 1718000000, "delay" => 0, "platform" => "3", "trainNumber" => "1" },
        { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718000600, "delay" => 0, "platform" => "2", "trainNumber" => "23153" },
        { "to" => "Lausanne", "category" => "IR", "number" => "IR90", "departure" => 1718001200, "delay" => 0, "platform" => "4", "trainNumber" => "2" },
        { "to" => "Coppet", "category" => "RL", "number" => "RL4", "departure" => 1718000600, "delay" => 1, "platform" => "2", "trainNumber" => "93153" },
    ];
    var parsed = ApiHandler.parseDepartureArray(deps);
    return parsed.size() == 3
        && parsed[0]["trainNum"].equals("1")
        && parsed[1]["trainNum"].equals("93153")
        && parsed[2]["trainNum"].equals("2");
}

(:test)
function testBuildFavouritesParam(logger) {
    Storage.deleteValue("favourites");
    FavouritesManager.addFavourite("8501120", "IC8", "Brig", "Lausanne");
    var param = FavouritesManager.buildFavouritesParam("8501120");
    Storage.deleteValue("favourites");
    return param != null && param.equals("IC8:Brig");
}

// trackStarted payload shape. transmit itself needs a live view + phone, so
// only the pure builder is covered.
(:test)
function testBuildTrackStartedFullPayload(logger) {
    var focused = { "dest" => "Bern", "depTs" => 1718000600, "line" => "IC1", "delay" => 2, "plat" => "7", "platChg" => true, "cat" => "IC", "trainNum" => "817", "opRef" => "11" };
    var data = PhoneSync.buildTrackStarted(focused, "8507000");
    return data["kind"].equals("trackStarted") && data["dest"].equals("Bern")
        && data["depTs"] == 1718000600 && data["line"].equals("IC1")
        && data["delay"] == 2 && data["plat"].equals("7") && data["platChg"] == true
        && data["cat"].equals("IC") && data["trainNum"].equals("817")
        && data["opRef"].equals("11") && data["stId"].equals("8507000");
}

(:test)
function testBuildTrackStartedOmitsOptionalFields(logger) {
    var focused = { "dest" => "Bern", "depTs" => 1718000600, "line" => "IC1", "delay" => 0, "plat" => "", "platChg" => false, "cat" => null, "trainNum" => null, "opRef" => null };
    var data = PhoneSync.buildTrackStarted(focused, null);
    return !data.hasKey("cat") && !data.hasKey("trainNum") && !data.hasKey("opRef") && !data.hasKey("stId")
        && data.hasKey("kind") && data.hasKey("dest") && data.hasKey("depTs")
        && data.hasKey("line") && data.hasKey("delay") && data.hasKey("plat") && data.hasKey("platChg");
}

(:test)
function testBuildTrackStartedNullFocused(logger) {
    return PhoneSync.buildTrackStarted(null, "8507000") == null;
}

// Liveness carries the version handshake so the phone can gate Send-to-Watch.
(:test)
function testBuildLivenessCarriesVersion(logger) {
    var data = PhoneSync.buildLiveness("hello");
    return data["kind"].equals("hello")
        && data["v"].equals(AppVersion.VERSION)
        && data["pv"] == PhoneSync.PROTOCOL_VERSION;
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
