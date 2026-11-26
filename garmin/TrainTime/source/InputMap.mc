// What each button, tap and swipe does in each app state. The delegate only
// maps the raw event in and performs the action out.
module InputMap {

    enum {
        EV_PAGE_NEXT,   // Down behaviour
        EV_PAGE_PREV,   // Up behaviour
        EV_SELECT,      // Select or Start behaviour
        EV_KEY_DOWN,
        EV_KEY_UP,
        EV_KEY_ENTER,
        EV_BACK,
        EV_MENU,
        EV_TAP,
        EV_SWIPE_UP,
        EV_SWIPE_DOWN
    }

    enum {
        ACT_NONE,       // declined, so the raw event follows
        ACT_EXIT_TO_BOARD,
        ACT_CYCLE_MODE,
        ACT_CYCLE_MODE_REVERSE,
        ACT_CURSOR_DOWN,
        ACT_CURSOR_UP,
        ACT_FORMATION_NEXT,
        ACT_FORMATION_PREV,
        ACT_ENTER_SELECTION,
        ACT_CYCLE_STATION,
        ACT_CONFIRM,
        ACT_MAP,
        ACT_CLOSE_FORMATION,
        ACT_EXIT_APP,
        ACT_SETTINGS_MENU,
        ACT_TRACKING_MENU,
        ACT_TRACK_ROW,
        ACT_MODE_MENU,
        ACT_SCROLL_DOWN,
        ACT_SCROLL_UP,
        ACT_STATION_MENU,
        ACT_SHOW_CAR,
        ACT_IGNORE      // taken, so the raw event does nothing
    }

    // hitKind is the BoardLayout.HIT_* under a tap, HIT_NONE off every target.
    // A behaviour runs before the raw event, and onTap or onSwipe only when
    // it declines. Touch screens decline the page and select behaviours, so
    // their buttons come back as raw keys.
    function action(event, state, isTouch, hitKind, cursorOnStation, formationOpen) {
        if (event == EV_PAGE_NEXT || event == EV_PAGE_PREV || event == EV_SELECT) {
            if (isTouch) { return ACT_NONE; }
        }
        if (event == EV_PAGE_NEXT || event == EV_KEY_DOWN) {
            return down(state);
        }
        if (event == EV_PAGE_PREV || event == EV_KEY_UP) {
            return up(state);
        }
        if (event == EV_SELECT || event == EV_KEY_ENTER) {
            return select(state, cursorOnStation);
        }
        if (event == EV_BACK) {
            // Back first closes the car readout, tracking ends on the next press
            if (state == 2 && formationOpen) { return ACT_CLOSE_FORMATION; }
            if (state == 1 || state == 2) { return ACT_EXIT_TO_BOARD; }
            return ACT_EXIT_APP;
        }
        if (event == EV_MENU) {
            return (state == 2) ? ACT_TRACKING_MENU : ACT_SETTINGS_MENU;
        }
        if (event == EV_TAP) {
            // Leaving tracking ends it on the phone too, so only the back
            // chevron leaves and a tap on nothing is taken and dropped
            if (state == 2) {
                if (hitKind == BoardLayout.HIT_BACK) { return ACT_EXIT_TO_BOARD; }
                if (hitKind == BoardLayout.HIT_WALK) { return ACT_MAP; }
                if (hitKind == BoardLayout.HIT_CAR) { return ACT_SHOW_CAR; }
                return ACT_IGNORE;
            }
            if (state <= 1) {
                if (hitKind == BoardLayout.HIT_ROW) { return ACT_TRACK_ROW; }
                if (hitKind == BoardLayout.HIT_MODE) { return ACT_MODE_MENU; }
                // A tap on the name lists every nearby station at once; Start
                // on the highlighted name still steps to the next one
                if (hitKind == BoardLayout.HIT_HEADER) {
                    if (isTouch) { return ACT_STATION_MENU; }
                    return (state == 1 && cursorOnStation) ? ACT_CYCLE_STATION : ACT_ENTER_SELECTION;
                }
            }
            return select(state, cursorOnStation);
        }
        // Swipes on the board page its rows and never change mode. A watch that
        // sends drags moves the rows with the finger instead, in the delegate
        if (event == EV_SWIPE_UP) {
            return (state <= 1) ? ACT_SCROLL_DOWN : down(state);
        }
        if (event == EV_SWIPE_DOWN) {
            return (state <= 1) ? ACT_SCROLL_UP : up(state);
        }
        return ACT_NONE;
    }

    function down(state) {
        if (state == 0) { return ACT_CYCLE_MODE; }
        if (state == 1) { return ACT_CURSOR_DOWN; }
        if (state == 2) { return ACT_FORMATION_NEXT; }
        return ACT_EXIT_TO_BOARD;
    }

    function up(state) {
        if (state == 0) { return ACT_CYCLE_MODE_REVERSE; }
        if (state == 1) { return ACT_CURSOR_UP; }
        if (state == 2) { return ACT_FORMATION_PREV; }
        return ACT_EXIT_TO_BOARD;
    }

    function select(state, cursorOnStation) {
        if (state == 0) { return ACT_ENTER_SELECTION; }
        if (state == 1) { return cursorOnStation ? ACT_CYCLE_STATION : ACT_CONFIRM; }
        if (state == 2) { return ACT_MAP; }
        return ACT_EXIT_TO_BOARD;
    }
}
