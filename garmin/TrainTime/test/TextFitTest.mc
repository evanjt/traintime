using Toybox.Test;

// How status text fits its slot, from measured widths.

// Helpers sit in a test module so they stay out of the app build and off the runner
(:test)
module FitCheck {

    function fitIs(r, t, f, lines) {
        return r[0] == t && r[1] == f && r[2] == lines;
    }
}

(:test)
function testSplitBreaksAtSpaceNearestMiddle(logger) {
    var h = TextFit.split("Fahrplan nicht abrufbar");
    var one = TextFit.split("Ausverkauft");
    return h[0].equals("Fahrplan nicht") && h[1].equals("abrufbar") && one == null;
}

(:test)
function testFitsOnOneLineInLargestFontFirst(logger) {
    return FitCheck.fitIs(TextFit.choose([[200, 170]], [[110, 95]], 250, 2), 0, 0, 1)
        && FitCheck.fitIs(TextFit.choose([[280, 230]], [[150, 125]], 250, 2), 0, 1, 1);
}

// Scenario: an outage message on the narrowest chord, too wide in both fonts.
// Expected behaviour: it wraps in the larger font before anything is cut.
(:test)
function testWrapsBeforeCuttingOnNarrowestChord(logger) {
    // A 390 px round screen 45% down with big fonts: 360 px of chord
    var r = TextFit.choose([[455, 400]], [[270, 236]], 360, 2);
    var cut = TextFit.choose([[455, 400]], [[380, 370]], 360, 2);
    var noBreak = TextFit.choose([[455, 400]], [[null, null]], 360, 2);
    return FitCheck.fitIs(r, 0, 0, 2) && FitCheck.fitIs(cut, 0, 1, 0) && FitCheck.fitIs(noBreak, 0, 1, 0);
}

// Scenario: the stale age line in a slot narrower than its full wording.
// Expected behaviour: the shorter wording is drawn whole, never a mid-word cut.
(:test)
function testAgeLineTakesShorterWordingOverCut(logger) {
    var r = TextFit.choose([[230], [190]], [[120], [100]], 200, 1);
    var neither = TextFit.choose([[230], [210]], [[120], [100]], 200, 1);
    return FitCheck.fitIs(r, 1, 0, 1) && FitCheck.fitIs(neither, 1, 0, 0);
}
