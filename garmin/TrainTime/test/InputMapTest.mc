using Toybox.Test;

// Scenario: every button in every app state, with touch off and on.
// Expected behaviour: buttons do what they did in 0.10.0. On a touch screen
// the page and select behaviours decline and the raw key gives the same action.

// Helpers sit in a test module so they stay out of the app build and off the runner
(:test)
module InputRows {

    // Rows: board, cursor on station, cursor on a row, tracking, tracking with
    // the car readout, inactive
    function inputRows() {
        return [
            [0, false, false],
            [1, true, false],
            [1, false, false],
            [2, false, false],
            [2, false, true],
            [3, false, false]
        ];
    }

    function inputMatches(event, keyEvent, expected, logger) {
        var rows = inputRows();
        var ok = true;
        for (var i = 0; i < rows.size(); i++) {
            var r = rows[i];
            var off = InputMap.action(event, r[0], false, BoardLayout.HIT_NONE, r[1], r[2]);
            var on = InputMap.action(keyEvent, r[0], true, BoardLayout.HIT_NONE, r[1], r[2]);
            if (off != expected[i] || on != expected[i]) {
                logger.debug("event " + event + " row " + i + ": off " + off + ", on " + on + ", want " + expected[i]);
                ok = false;
            }
        }
        return ok;
    }
}

(:test)
function testDownButtonInEveryState(logger) {
    return InputRows.inputMatches(InputMap.EV_PAGE_NEXT, InputMap.EV_KEY_DOWN, [
        InputMap.ACT_CYCLE_MODE,
        InputMap.ACT_CURSOR_DOWN,
        InputMap.ACT_CURSOR_DOWN,
        InputMap.ACT_FORMATION_NEXT,
        InputMap.ACT_FORMATION_NEXT,
        InputMap.ACT_EXIT_TO_BOARD
    ], logger);
}

(:test)
function testUpButtonInEveryState(logger) {
    return InputRows.inputMatches(InputMap.EV_PAGE_PREV, InputMap.EV_KEY_UP, [
        InputMap.ACT_CYCLE_MODE_REVERSE,
        InputMap.ACT_CURSOR_UP,
        InputMap.ACT_CURSOR_UP,
        InputMap.ACT_FORMATION_PREV,
        InputMap.ACT_FORMATION_PREV,
        InputMap.ACT_EXIT_TO_BOARD
    ], logger);
}

(:test)
function testSelectButtonInEveryState(logger) {
    return InputRows.inputMatches(InputMap.EV_SELECT, InputMap.EV_KEY_ENTER, [
        InputMap.ACT_ENTER_SELECTION,
        InputMap.ACT_CYCLE_STATION,
        InputMap.ACT_CONFIRM,
        InputMap.ACT_MAP,
        InputMap.ACT_MAP,
        InputMap.ACT_EXIT_TO_BOARD
    ], logger);
}

(:test)
function testBackButtonInEveryState(logger) {
    return InputRows.inputMatches(InputMap.EV_BACK, InputMap.EV_BACK, [
        InputMap.ACT_EXIT_APP,
        InputMap.ACT_EXIT_TO_BOARD,
        InputMap.ACT_EXIT_TO_BOARD,
        InputMap.ACT_EXIT_TO_BOARD,
        InputMap.ACT_CLOSE_FORMATION,
        InputMap.ACT_EXIT_APP
    ], logger);
}

(:test)
function testMenuHoldInEveryState(logger) {
    return InputRows.inputMatches(InputMap.EV_MENU, InputMap.EV_MENU, [
        InputMap.ACT_SETTINGS_MENU,
        InputMap.ACT_SETTINGS_MENU,
        InputMap.ACT_SETTINGS_MENU,
        InputMap.ACT_TRACKING_MENU,
        InputMap.ACT_TRACKING_MENU,
        InputMap.ACT_SETTINGS_MENU
    ], logger);
}

(:test)
function testRawKeysMatchBehavioursWithTouchOff(logger) {
    var rows = InputRows.inputRows();
    var pairs = [
        [InputMap.EV_PAGE_NEXT, InputMap.EV_KEY_DOWN],
        [InputMap.EV_PAGE_PREV, InputMap.EV_KEY_UP],
        [InputMap.EV_SELECT, InputMap.EV_KEY_ENTER]
    ];
    for (var i = 0; i < rows.size(); i++) {
        var r = rows[i];
        for (var p = 0; p < pairs.size(); p++) {
            var a = InputMap.action(pairs[p][0], r[0], false, BoardLayout.HIT_NONE, r[1], r[2]);
            var b = InputMap.action(pairs[p][1], r[0], false, BoardLayout.HIT_NONE, r[1], r[2]);
            if (a != b) { return false; }
        }
    }
    return true;
}

(:test)
function testTouchScreenDeclinesPageAndSelectBehaviours(logger) {
    var rows = InputRows.inputRows();
    var events = [InputMap.EV_PAGE_NEXT, InputMap.EV_PAGE_PREV, InputMap.EV_SELECT];
    for (var i = 0; i < rows.size(); i++) {
        var r = rows[i];
        for (var e = 0; e < events.size(); e++) {
            if (InputMap.action(events[e], r[0], true, BoardLayout.HIT_NONE, r[1], r[2]) != InputMap.ACT_NONE) {
                return false;
            }
        }
    }
    return true;
}

(:test)
function testTapOnRowTracksIt(logger) {
    return InputMap.action(InputMap.EV_TAP, 0, true, BoardLayout.HIT_ROW, false, false) == InputMap.ACT_TRACK_ROW
        && InputMap.action(InputMap.EV_TAP, 1, true, BoardLayout.HIT_ROW, true, false) == InputMap.ACT_TRACK_ROW
        && InputMap.action(InputMap.EV_TAP, 1, true, BoardLayout.HIT_ROW, false, false) == InputMap.ACT_TRACK_ROW;
}

(:test)
function testTapOnHeaderOpensStationMenu(logger) {
    return InputMap.action(InputMap.EV_TAP, 0, true, BoardLayout.HIT_HEADER, false, false) == InputMap.ACT_STATION_MENU
        && InputMap.action(InputMap.EV_TAP, 1, true, BoardLayout.HIT_HEADER, true, false) == InputMap.ACT_STATION_MENU
        && InputMap.action(InputMap.EV_TAP, 1, true, BoardLayout.HIT_HEADER, false, false) == InputMap.ACT_STATION_MENU;
}

// Buttons still reach the next station one press at a time
(:test)
function testStartOnHighlightedNameCyclesStation(logger) {
    return InputMap.action(InputMap.EV_KEY_ENTER, 1, true, BoardLayout.HIT_NONE, true, false) == InputMap.ACT_CYCLE_STATION
        && InputMap.action(InputMap.EV_SELECT, 1, false, BoardLayout.HIT_NONE, true, false) == InputMap.ACT_CYCLE_STATION;
}

(:test)
function testTapOnModeBandOpensModeMenu(logger) {
    return InputMap.action(InputMap.EV_TAP, 0, true, BoardLayout.HIT_MODE, false, false) == InputMap.ACT_MODE_MENU
        && InputMap.action(InputMap.EV_TAP, 1, true, BoardLayout.HIT_MODE, false, false) == InputMap.ACT_MODE_MENU;
}

// A tap on nothing, or anywhere off the board, acts as the select button
(:test)
function testTapOnNothingActsAsSelect(logger) {
    var rows = InputRows.inputRows();
    for (var i = 0; i < rows.size(); i++) {
        var r = rows[i];
        if (r[0] == 2) { continue; }
        var tap = InputMap.action(InputMap.EV_TAP, r[0], true, BoardLayout.HIT_NONE, r[1], r[2]);
        var key = InputMap.action(InputMap.EV_KEY_ENTER, r[0], true, BoardLayout.HIT_NONE, r[1], r[2]);
        if (tap != key) { return false; }
    }
    return true;
}

(:test)
function testSwipeScrollsBoardAndPagesOtherwise(logger) {
    var rows = InputRows.inputRows();
    var ok = true;
    for (var i = 0; i < rows.size(); i++) {
        var r = rows[i];
        var up = InputMap.action(InputMap.EV_SWIPE_UP, r[0], true, BoardLayout.HIT_NONE, r[1], r[2]);
        var down = InputMap.action(InputMap.EV_SWIPE_DOWN, r[0], true, BoardLayout.HIT_NONE, r[1], r[2]);
        if (r[0] <= 1) {
            ok = ok && up == InputMap.ACT_SCROLL_DOWN && down == InputMap.ACT_SCROLL_UP;
        } else {
            ok = ok
                && up == InputMap.action(InputMap.EV_KEY_DOWN, r[0], true, BoardLayout.HIT_NONE, r[1], r[2])
                && down == InputMap.action(InputMap.EV_KEY_UP, r[0], true, BoardLayout.HIT_NONE, r[1], r[2]);
        }
    }
    return ok;
}

// Scenario: leaving tracking ends it on the watch and the phone, so a brushed
// sleeve must not leave it or open a screen.
// Expected behaviour: a tap acts on the target under it and anywhere else is
// taken and ignored, with or without the car readout up.
(:test)
function testTrackingTapActsOnWhatItLandsOn(logger) {
    var ok = true;
    var open = [false, true];
    for (var i = 0; i < open.size(); i++) {
        ok = ok
            && InputMap.action(InputMap.EV_TAP, 2, true, BoardLayout.HIT_BACK, false, open[i]) == InputMap.ACT_EXIT_TO_BOARD
            && InputMap.action(InputMap.EV_TAP, 2, true, BoardLayout.HIT_WALK, false, open[i]) == InputMap.ACT_MAP
            && InputMap.action(InputMap.EV_TAP, 2, true, BoardLayout.HIT_CAR, false, open[i]) == InputMap.ACT_SHOW_CAR
            && InputMap.action(InputMap.EV_TAP, 2, true, BoardLayout.HIT_NONE, false, open[i]) == InputMap.ACT_IGNORE;
    }
    return ok;
}

(:test)
function testStartStillOpensMapWhileTracking(logger) {
    return InputMap.action(InputMap.EV_SELECT, 2, false, BoardLayout.HIT_NONE, false, false) == InputMap.ACT_MAP
        && InputMap.action(InputMap.EV_KEY_ENTER, 2, false, BoardLayout.HIT_NONE, false, false) == InputMap.ACT_MAP
        && InputMap.action(InputMap.EV_KEY_ENTER, 2, true, BoardLayout.HIT_NONE, false, false) == InputMap.ACT_MAP;
}
