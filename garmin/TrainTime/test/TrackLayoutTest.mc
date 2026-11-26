using Toybox.Math;
using Toybox.Test;

// Tap targets on the tracking screen, against the geometry the renderer draws with:
// a 260 and a 454 round screen and a 320 x 360 rectangular one.

// Helpers sit in a test module so they stay out of the app build and off the runner
(:test)
module TrackHits {

    function hitIs(h, kind, index) {
        return h[0] == kind && h[1] == index;
    }

    // Font heights: extra tiny, tiny, small, medium
    function fonts(width) {
        if (width == 260) { return [19, 22, 26, 31]; }
        if (width == 454) { return [37, 44, 52, 62]; }
        return [39, 44, 51, 59];
    }

    // Bottom of the status line, where the walk target starts
    function statusBottom(width, height, round) {
        var f = fonts(width);
        return TrackLayout.rows(width, height, round, f[0], f[1], f[2], f[3], false)[:status] + f[1];
    }

    // An eight-car band as the round renderer lays it out
    function roundStrip(width) {
        var breaks = [false, false, false, false, false, false, false, false];
        var g = FormationArc.layout(width, statusBottom(width, width, true), 8, 0);
        return TrackLayout.roundStrip(g, FormationArc.spans(g, breaks));
    }

    // A point on the band's mid radius in the middle of car i
    function onCar(width, i) {
        var breaks = [false, false, false, false, false, false, false, false];
        var g = FormationArc.layout(width, statusBottom(width, width, true), 8, 0);
        var sp = FormationArc.spans(g, breaks);
        return FormationArc.point(g, g[:rm], (sp[i][0] + sp[i][1]) / 2);
    }

    function rectRows() {
        var f = fonts(320);
        var t = TrackLayout.rows(320, 360, false, f[0], f[1], f[2], f[3], false);
        return FormationStrip.rows(320, 360, t[:walk], f[0]);
    }

    function rectSpans() {
        var breaks = [false, false, false, false, false, false, false, false];
        var g = FormationStrip.layout(320, 310, 8, 0);
        return FormationStrip.spans(g, breaks);
    }

    function rectStrip() {
        return TrackLayout.rectStrip(rectRows(), rectSpans());
    }
}

// Scenario: the back chevron must take a fingertip on every touch screen.
// Expected behaviour: its target is at least 7 mm on a side, at about 7.9 px/mm on
// the 260 and 280 round screens, 12.8 on 390 to 454 and 13.4 on the 320 x 360 one.
(:test)
function testBackTargetTakesAFingertip(logger) {
    return TrackLayout.backSize(260) >= 56 && TrackLayout.backSize(280) >= 56
        && TrackLayout.backSize(390) >= 90 && TrackLayout.backSize(454) >= 90
        && TrackLayout.backSize(320) >= 94;
}

(:test)
function testTapOnBackChevronLeaves(logger) {
    return TrackHits.hitIs(TrackLayout.hit(12, 130, 260, 260, 168, TrackHits.roundStrip(260)), BoardLayout.HIT_BACK, 0)
        && TrackHits.hitIs(TrackLayout.hit(40, 160, 260, 260, null, null), BoardLayout.HIT_BACK, 0)
        && TrackHits.hitIs(TrackLayout.hit(14, 227, 454, 454, null, TrackHits.roundStrip(454)), BoardLayout.HIT_BACK, 0)
        && TrackHits.hitIs(TrackLayout.hit(20, 180, 320, 360, null, TrackHits.rectStrip()), BoardLayout.HIT_BACK, 0);
}

// Scenario: a tap in the middle of the countdown, or on the status line.
// Expected behaviour: it lands on nothing.
(:test)
function testTapOnCountdownHitsNothing(logger) {
    var s260 = TrackHits.statusBottom(260, 260, true);
    var s454 = TrackHits.statusBottom(454, 454, true);
    var sRect = TrackHits.statusBottom(320, 360, false);
    return TrackHits.hitIs(TrackLayout.hit(130, 105, 260, 260, s260, TrackHits.roundStrip(260)), BoardLayout.HIT_NONE, 0)
        && TrackHits.hitIs(TrackLayout.hit(130, s260 - 5, 260, 260, s260, TrackHits.roundStrip(260)), BoardLayout.HIT_NONE, 0)
        && TrackHits.hitIs(TrackLayout.hit(227, 190, 454, 454, s454, TrackHits.roundStrip(454)), BoardLayout.HIT_NONE, 0)
        && TrackHits.hitIs(TrackLayout.hit(160, 150, 320, 360, sRect, TrackHits.rectStrip()), BoardLayout.HIT_NONE, 0)
        && TrackHits.hitIs(TrackLayout.hit(227, 60, 454, 454, s454, null), BoardLayout.HIT_NONE, 0);
}

(:test)
function testTapOnWalkLineOpensMap(logger) {
    var s260 = TrackHits.statusBottom(260, 260, true);
    var s454 = TrackHits.statusBottom(454, 454, true);
    var r = TrackHits.rectRows();
    return TrackHits.hitIs(TrackLayout.hit(130, s260 + 8, 260, 260, s260, TrackHits.roundStrip(260)), BoardLayout.HIT_WALK, 0)
        && TrackHits.hitIs(TrackLayout.hit(227, s454 + 15, 454, 454, s454, TrackHits.roundStrip(454)), BoardLayout.HIT_WALK, 0)
        && TrackHits.hitIs(TrackLayout.hit(227, 420, 454, 454, s454, null), BoardLayout.HIT_WALK, 0)
        && TrackHits.hitIs(TrackLayout.hit(160, r[:row] + 15, 320, 360,
            TrackHits.statusBottom(320, 360, false), TrackHits.rectStrip()), BoardLayout.HIT_WALK, 0);
}

// Scenario: the car readout is up in the walk line's place.
// Expected behaviour: the row is no longer a target for the map.
(:test)
function testTapOnReadoutRowHitsNothing(logger) {
    var s260 = TrackHits.statusBottom(260, 260, true);
    return TrackHits.hitIs(TrackLayout.hit(130, s260 + 8, 260, 260, null, TrackHits.roundStrip(260)), BoardLayout.HIT_NONE, 0);
}

(:test)
function testTapOnCarPicksThatCar(logger) {
    var ok = true;
    var widths = [260, 454];
    var cars = [0, 3, 7];
    for (var w = 0; w < widths.size(); w++) {
        var width = widths[w];
        var s = TrackHits.statusBottom(width, width, true);
        for (var c = 0; c < cars.size(); c++) {
            var p = TrackHits.onCar(width, cars[c]);
            ok = ok && TrackHits.hitIs(TrackLayout.hit(p[0], p[1], width, width, s, TrackHits.roundStrip(width)),
                BoardLayout.HIT_CAR, cars[c]);
        }
    }
    var r = TrackHits.rectRows();
    var sp = TrackHits.rectSpans();
    var sRect = TrackHits.statusBottom(320, 360, false);
    for (var c = 0; c < cars.size(); c++) {
        var x = (sp[cars[c]][0] + sp[cars[c]][1]) / 2;
        ok = ok && TrackHits.hitIs(TrackLayout.hit(x, r[:car] + 4, 320, 360, sRect, TrackHits.rectStrip()),
            BoardLayout.HIT_CAR, cars[c]);
    }
    return ok;
}

// Scenario: a tap on the gap between cars, or on the nose, on a narrow strip.
// Expected behaviour: the nearest car opens.
(:test)
function testTapBesideCarsPicksNearest(logger) {
    var r = TrackHits.rectRows();
    var sp = TrackHits.rectSpans();
    var sRect = TrackHits.statusBottom(320, 360, false);
    var s260 = TrackHits.statusBottom(260, 260, true);
    var end = TrackHits.onCar(260, 7);
    return TrackHits.hitIs(TrackLayout.hit(sp[0][0] - 6, r[:car] + 4, 320, 360, sRect, TrackHits.rectStrip()),
            BoardLayout.HIT_CAR, 0)
        && TrackHits.hitIs(TrackLayout.hit(sp[3][1] + 1, r[:letters] + 2, 320, 360, sRect, TrackHits.rectStrip()),
            BoardLayout.HIT_CAR, 3)
        && TrackHits.hitIs(TrackLayout.hit(end[0] + 4, end[1] - 3, 260, 260, s260, TrackHits.roundStrip(260)),
            BoardLayout.HIT_CAR, 7);
}
