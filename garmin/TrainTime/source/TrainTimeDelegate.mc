using Toybox.WatchUi;

class TrainTimeDelegate extends WatchUi.BehaviorDelegate {

    private var mView;
    // Where the finger went down and the offset the board had then, while a
    // drag is under way
    private var mDragY;
    private var mDragFrom;
    // A watch that sends drags moves the board with them, so its swipes no
    // longer page the board
    private var mDrags = false;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onNextPage() {
        return route(InputMap.EV_PAGE_NEXT, null);
    }

    function onPreviousPage() {
        return route(InputMap.EV_PAGE_PREV, null);
    }

    function onSelect() {
        return route(InputMap.EV_SELECT, null);
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER) { return route(InputMap.EV_KEY_ENTER, null); }
        if (key == WatchUi.KEY_DOWN) { return route(InputMap.EV_KEY_DOWN, null); }
        if (key == WatchUi.KEY_UP) { return route(InputMap.EV_KEY_UP, null); }
        return false;
    }

    (:touch)
    function onSwipe(swipeEvent) {
        var dir = swipeEvent.getDirection();
        if (dir == WatchUi.SWIPE_UP) { return route(InputMap.EV_SWIPE_UP, null); }
        if (dir == WatchUi.SWIPE_DOWN) { return route(InputMap.EV_SWIPE_DOWN, null); }
        return false;
    }

    (:touch)
    function onDrag(dragEvent) {
        mDrags = true;
        var y = dragEvent.getCoordinates()[1];
        var type = dragEvent.getType();
        if (type == WatchUi.DRAG_TYPE_START) {
            mDragY = y;
            mDragFrom = mView.mScrollOffset;
        } else if (mDragY != null) {
            mView.dragBoard(mDragFrom, y - mDragY);
            mView.mLastInteractionTime = Toybox.Time.now().value();
            if (type == WatchUi.DRAG_TYPE_STOP) { mDragY = null; }
        }
        // Declined, so the tap and swipe that end a touch still follow
        return false;
    }

    // A flick carries the board on from where the drag left it
    (:touch)
    function onFlick(flickEvent) {
        mDragY = null;
        mView.dragBoard(mView.mScrollOffset,
            BoardLayout.flickTravel(flickEvent.getVelocity(), flickEvent.getDirection()));
        return false;
    }

    (:touch)
    function onTap(clickEvent) {
        var xy = clickEvent.getCoordinates();
        return route(InputMap.EV_TAP, mView.tapHit(xy[0], xy[1]));
    }

    function onBack() {
        return route(InputMap.EV_BACK, null);
    }

    function onMenu() {
        return route(InputMap.EV_MENU, null);
    }

    private function route(event, hit) {
        var state = mView.getAppState();
        var hitKind = (hit != null) ? hit[0] : BoardLayout.HIT_NONE;
        // Reading the readout clears it once lapsed, so only Back asks
        var formationOpen = event == InputMap.EV_BACK && state == 2 && mView.formationCursor() != null;
        var action = InputMap.action(event, state, DrawUtils.isTouch(), hitKind,
            mView.mCursorIndex == -1, formationOpen);
        if (action == InputMap.ACT_NONE) { return false; }
        if (event != InputMap.EV_MENU) {
            mView.mLastInteractionTime = Toybox.Time.now().value();
        }
        return perform(action, (hit != null) ? hit[1] : 0);
    }

    private function perform(action, index) {
        if (action == InputMap.ACT_EXIT_TO_BOARD) {
            mView.exitToStationView();
        } else if (action == InputMap.ACT_CYCLE_MODE) {
            mView.cycleMode();
        } else if (action == InputMap.ACT_CYCLE_MODE_REVERSE) {
            mView.cycleModeReverse();
        } else if (action == InputMap.ACT_CURSOR_DOWN) {
            mView.moveCursorDown();
        } else if (action == InputMap.ACT_CURSOR_UP) {
            mView.moveCursorUp();
        } else if (action == InputMap.ACT_FORMATION_NEXT) {
            mView.moveFormationCursor(1);
        } else if (action == InputMap.ACT_FORMATION_PREV) {
            mView.moveFormationCursor(-1);
        } else if (action == InputMap.ACT_ENTER_SELECTION) {
            mView.enterTrainSelection();
        } else if (action == InputMap.ACT_CYCLE_STATION) {
            mView.cycleStation();
        } else if (action == InputMap.ACT_CONFIRM) {
            mView.confirmTrainSelection();
        } else if (action == InputMap.ACT_MAP) {
            mView.enterMapView();
        } else if (action == InputMap.ACT_CLOSE_FORMATION) {
            mView.mFormationCursor = null;
            WatchUi.requestUpdate();
        } else if (action == InputMap.ACT_EXIT_APP) {
            // Tell the phone first so its link indicator flips to "closed"
            // immediately instead of waiting for pings to lapse.
            PhoneSync.sendClosing();
            System.exit();
            return false;
        } else if (action == InputMap.ACT_SETTINGS_MENU) {
            SettingsMenu.open(mView);
        } else if (action == InputMap.ACT_TRACKING_MENU) {
            FavouritesMenu.openTrackingMenu(mView);
        } else if (action == InputMap.ACT_TRACK_ROW) {
            mView.trackRow(index);
        } else if (action == InputMap.ACT_MODE_MENU || action == InputMap.ACT_STATION_MENU) {
            openList(action);
        } else if (action == InputMap.ACT_SCROLL_DOWN) {
            if (!mDrags) { mView.scrollBoard(1); }
        } else if (action == InputMap.ACT_SCROLL_UP) {
            if (!mDrags) { mView.scrollBoard(-1); }
        } else if (action == InputMap.ACT_SHOW_CAR) {
            mView.showFormationCar(index);
        }
        return true;
    }

    (:touch)
    private function openList(action) {
        if (action == InputMap.ACT_MODE_MENU) {
            ModeMenu.open(mView);
        } else {
            StationMenu.open(mView);
        }
    }

    // Lists open only from a tap, which a button-only watch never sends
    (:notouch)
    private function openList(action) {
    }
}
