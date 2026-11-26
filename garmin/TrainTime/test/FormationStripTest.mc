using Toybox.Test;

// The straight formation strip on a 320 x 360 rectangular screen, whose fonts are
// 39 (extra tiny), 44 (tiny), 51 (small) and 59 (medium) pixels high.

// Helpers sit in a test module so they stay out of the app build and off the runner
(:test)
module StripFit {

    // Two digits in the strip's number font at that width
    const STRIP_LABEL_W = 22;

    function stripFits(breaks) {
        var count = breaks.size();
        var g = FormationStrip.layout(320, 310, count, FormationArc.breakCount(breaks));
        var sp = FormationStrip.spans(g, breaks);
        if (g[:x] < 5 || sp[count - 1][1] > 315) { return false; }
        for (var i = 0; i < count; i++) {
            if (sp[i][1] - sp[i][0] < STRIP_LABEL_W) { return false; }
            if (i > 0 && sp[i][0] <= sp[i - 1][1]) { return false; }
        }
        return true;
    }
}

// Scenario: a five-car and an eight-car train on the rectangular screen.
// Expected behaviour: every car is at least as wide as a two-digit number and the strip stays inside the usable width.
(:test)
function testStripCarsHoldTheirNumber(logger) {
    return StripFit.stripFits([false, false, false, false, false])
        && StripFit.stripFits([false, false, false, true, false, false, false, false]);
}

(:test)
function testStripNumbersEveryCarOfAnEightCarTrain(logger) {
    var numbers = [12, 11, 10, 9, 8, 7, 6, 5];
    var classes = [2, 2, 2, 2, 2, 1, 1, 2];
    var breaks = [false, false, false, false, false, false, false, false];
    var g = FormationStrip.layout(320, 310, 8, 0);
    var labels = FormationArc.numberLabels(numbers, classes, breaks, FormationStrip.spans(g, breaks), 0, g[:k]);
    if (labels.size() != 8) { return false; }
    for (var i = 0; i < 8; i++) {
        if (labels[i][0] != i || labels[i][1] != i || !labels[i][2].equals(numbers[i].toString())) { return false; }
    }
    return true;
}

// Scenario: sixteen cars are each narrower than a two-digit number.
// Expected behaviour: numbers merge into ranges that fit their cars, cover every car once and stop at the unit boundary.
(:test)
function testStripLongTrainMergesNumbersIntoRanges(logger) {
    var t = FormationFixture.formationFixture();
    var g = FormationStrip.layout(320, 310, 16, 1);
    var sp = FormationStrip.spans(g, t[:breaks]);
    if (sp[15][1] > 315) { return false; }
    var labels = FormationArc.numberLabels(t[:numbers], t[:classes], t[:breaks], sp, 0, g[:k]);
    var seen = new [16];
    for (var q = 0; q < labels.size(); q++) {
        var a = labels[q][0];
        var b = labels[q][1];
        if (a <= 7 && b >= 8) { return false; }
        if (labels[q][2].length() * 12 - 2 > sp[b][1] - sp[a][0]) { return false; }
        for (var i = a; i <= b; i++) {
            if (seen[i] != null) { return false; }
            seen[i] = true;
        }
    }
    for (var i = 0; i < 16; i++) { if (seen[i] == null) { return false; } }
    return true;
}

// Scenario: tracking a train with a formation on the rectangular screen.
// Expected behaviour: the walk or readout row sits under the status line and clear of the strip.
(:test)
function testStripLeavesARowForTheReadout(logger) {
    var t = TrackLayout.rows(320, 360, false, 39, 44, 51, 59, false);
    var s = FormationStrip.rows(320, 360, t[:walk], 39);
    return s[:row] == t[:walk] && s[:row] + 39 <= s[:letters]
        && s[:line] + FormationStrip.lineH(320) <= 360;
}

// Scenario: a round screen, where the bezel band needs none of the rows' room.
// Expected behaviour: the rows keep their full leading.
(:test)
function testRoundTrackingRowsKeepTheirLeading(logger) {
    var t = TrackLayout.rows(260, 260, true, 19, 22, 26, 31, false);
    return TrackLayout.top(260, true) == 7 && TrackLayout.destY(260, 260, true, 19) == 47
        && t[:plat] == 74 && t[:countdown] == 95 && t[:bar] == 128 && t[:status] == 146
        && t[:walk] == 170 && t[:route] == null;
}
