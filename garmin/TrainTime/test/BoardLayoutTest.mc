using Toybox.Test;

// Tap targets on the board, against the geometry the renderer draws with.

// Helpers sit in a test module so they stay out of the app build and off the runner
(:test)
module BoardHits {

    function hitIs(h, kind, index) {
        return h[0] == kind && h[1] == index;
    }
}

// Scenario: the mode icons are about 4 mm wide, too small to hit reliably.
// Expected behaviour: the whole band above the walk line is one target.
(:test)
function testTapAnywhereInModeBandHitsTheBand(logger) {
    // 390 round: icons centred at x 114, 168, 222, 276 on y 27, the walk line at y 50
    return BoardHits.hitIs(BoardLayout.hit(222, 27, 390, 390, 4), BoardLayout.HIT_MODE, 0)
        && BoardHits.hitIs(BoardLayout.hit(141, 27, 390, 390, 4), BoardLayout.HIT_MODE, 0)
        && BoardHits.hitIs(BoardLayout.hit(40, 27, 390, 390, 4), BoardLayout.HIT_MODE, 0)
        && BoardHits.hitIs(BoardLayout.hit(350, 10, 390, 390, 4), BoardLayout.HIT_MODE, 0)
        && BoardHits.hitIs(BoardLayout.hit(195, 49, 390, 390, 4), BoardLayout.HIT_MODE, 0)
        && BoardHits.hitIs(BoardLayout.hit(20, 20, 260, 260, 4), BoardLayout.HIT_MODE, 0);
}

(:test)
function testTapOnStationNameHitsHeader(logger) {
    return BoardHits.hitIs(BoardLayout.hit(195, 86, 390, 390, 4), BoardLayout.HIT_HEADER, 0)
        && BoardHits.hitIs(BoardLayout.hit(130, 60, 260, 260, 4), BoardLayout.HIT_HEADER, 0);
}

(:test)
function testTapOnRowPicksThatRow(logger) {
    // 390: rows start at y 140, 54 apart. The second row's text spans about 194 to 232
    return BoardHits.hitIs(BoardLayout.hit(260, 205, 390, 390, 4), BoardLayout.HIT_ROW, 1)
        && BoardHits.hitIs(BoardLayout.hit(195, 150, 390, 390, 4), BoardLayout.HIT_ROW, 0)
        && BoardHits.hitIs(BoardLayout.hit(195, 322, 390, 390, 4), BoardLayout.HIT_ROW, 3)
        && BoardHits.hitIs(BoardLayout.hit(130, 100, 260, 260, 4), BoardLayout.HIT_ROW, 0);
}

(:test)
function testTapBelowDrawnRowsHitsNothing(logger) {
    // Two rows drawn: the third band is empty, and the bottom hint is never a row
    return BoardHits.hitIs(BoardLayout.hit(195, 270, 390, 390, 2), BoardLayout.HIT_NONE, 0)
        && BoardHits.hitIs(BoardLayout.hit(195, 359, 390, 390, 4), BoardLayout.HIT_NONE, 0)
        && BoardHits.hitIs(BoardLayout.hit(195, 205, 390, 390, 0), BoardLayout.HIT_NONE, 0);
}

(:test)
function testVisibleRowsFollowScrollAndScreen(logger) {
    return BoardLayout.visibleRows(10, 0, 390) == 4
        && BoardLayout.visibleRows(10, 8, 390) == 2
        && BoardLayout.visibleRows(10, 0, 218) == 3
        && BoardLayout.visibleRows(2, 0, 390) == 2
        && BoardLayout.visibleRows(3, 5, 390) == 0;
}

// Scenario: one column layout per device, from its font metrics.
// Expected behaviour: a screen whose fonts fit keeps today's columns, while
// big fonts push the minutes inside the circle and widen the line slot to the id.
(:test)
function testColumnsKeepPercentagesWhenFontsFit(logger) {
    // fenix 6 Pro class: 260 px, small fonts, last row edge at 20 px
    var c = BoardLayout.columns(260, 20, 30, 18, 26, 3);
    return c[0] == 52 && c[1] == 54 && c[2] == 83 && c[3] == 28 && c[4] == 114;
}

(:test)
function testColumnsMakeRoomForBigFonts(logger) {
    // vivoactive 5 class: 390 px, last row edge at 70 px, "jetzt" 62 px, "IR95" 60 px
    var c = BoardLayout.columns(390, 70, 62, 34, 60, 5);
    var minRight = c[0];
    var slotX = c[2];
    var slotW = c[3];
    return minRight - 62 >= 70
        && slotX >= c[1] + 34
        && slotW >= 60
        && c[4] >= slotX + slotW;
}

(:test)
function testLineChipCentresInItsSlot(logger) {
    return BoardLayout.chipX(100, 40, 12) == 114
        && BoardLayout.chipX(100, 40, 40) == 100
        && BoardLayout.chipX(100, 40, 400) == 100;
}

(:test)
function testHintsFollowTouchState(logger) {
    return BoardLayout.hintKind(false) == BoardLayout.HINT_ARCS
        && BoardLayout.hintKind(true) == BoardLayout.HINT_CHEVRONS;
}

(:test)
function testResumeWordingFollowsTouchState(logger) {
    return BoardLayout.resumeHint(true) == Rez.Strings.TapResume
        && BoardLayout.resumeHint(false) == Rez.Strings.PressResume
        && BoardLayout.resumeHint(true) != BoardLayout.resumeHint(false);
}

// Scenario: a finger dragged on the board, then lifted.
// Expected behaviour: the rows move by the distance dragged, snapped to the
// nearest whole row, and stop at the first and last screenful.
(:test)
function testDragMovesOneRowPerRowSpacing(logger) {
    // Rows sit 36 px apart on 260, 63 on 454 round and 50 on a 320x360 rectangle
    return BoardLayout.scrollOffset(0, -36, 260, 12) == 1
        && BoardLayout.scrollOffset(3, 36, 260, 12) == 2
        && BoardLayout.scrollOffset(0, -63, 454, 12) == 1
        && BoardLayout.scrollOffset(0, -50, 360, 12) == 1
        && BoardLayout.scrollOffset(2, 0, 454, 12) == 2;
}

(:test)
function testDragSnapsToNearestRow(logger) {
    // Under half a row stays, over half a row moves
    return BoardLayout.scrollOffset(0, -17, 260, 12) == 0
        && BoardLayout.scrollOffset(0, -19, 260, 12) == 1
        && BoardLayout.scrollOffset(4, 30, 454, 12) == 4
        && BoardLayout.scrollOffset(4, 33, 454, 12) == 3;
}

(:test)
function testLongDragMovesSeveralRows(logger) {
    return BoardLayout.scrollOffset(0, -150, 260, 12) == 4
        && BoardLayout.scrollOffset(1, -190, 454, 12) == 4
        && BoardLayout.scrollOffset(6, 150, 360, 12) == 3;
}

(:test)
function testScrollClampsAtTopAndBottom(logger) {
    // Twelve rows, four on screen: the last screenful starts at row 8
    return BoardLayout.scrollOffset(1, 200, 260, 12) == 0
        && BoardLayout.scrollOffset(6, -400, 454, 12) == 8
        && BoardLayout.scrollOffset(0, -400, 360, 12) == 8
        && BoardLayout.scrollOffset(0, -400, 218, 5) == 2
        && BoardLayout.scrollOffset(0, -200, 454, 3) == 0
        && BoardLayout.scrollOffset(0, -200, 454, 0) == 0;
}

// Scenario: a fast flick at the end of a drag.
// Expected behaviour: the board carries on in the flick's direction, further
// the faster it was, and only an up or down flick moves it.
(:test)
function testFlickCarriesFurtherWithSpeed(logger) {
    var slow = BoardLayout.scrollOffset(0, BoardLayout.flickTravel(400.0f, 0), 454, 30);
    var fast = BoardLayout.scrollOffset(0, BoardLayout.flickTravel(1600.0f, 0), 454, 30);
    var down = BoardLayout.scrollOffset(20, BoardLayout.flickTravel(1600.0f, 180), 454, 30);
    return slow >= 1 && fast > slow && 20 - down == fast
        && BoardLayout.scrollOffset(0, BoardLayout.flickTravel(1600.0f, 10), 260, 30) > 0
        && BoardLayout.flickTravel(1600.0f, 90) == 0
        && BoardLayout.flickTravel(1600.0f, 270) == 0
        && BoardLayout.scrollOffset(0, BoardLayout.flickTravel(9000.0f, 0), 360, 12) == 8;
}
