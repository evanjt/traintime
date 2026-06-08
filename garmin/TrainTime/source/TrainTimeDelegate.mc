using Toybox.WatchUi;

class TrainTimeDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onNextPage() {  // Down button
        mView.mLastInteractionTime = Toybox.Time.now().value();
        var state = mView.getAppState();
        if (state == 3) {
            mView.exitToStationView();
        } else if (state == 0) {
            mView.cycleMode();            // cycle modes forward
        } else if (state == 1) {
            mView.moveCursorDown();
        }
        // State 2: no-op
        return true;
    }

    function onPreviousPage() {  // Up button
        mView.mLastInteractionTime = Toybox.Time.now().value();
        var state = mView.getAppState();
        if (state == 3) {
            mView.exitToStationView();
        } else if (state == 0) {
            mView.cycleModeReverse();     // cycle modes backward
        } else if (state == 1) {
            mView.moveCursorUp();
        }
        // State 2: no-op
        return true;
    }

    function onSelect() {
        mView.mLastInteractionTime = Toybox.Time.now().value();
        var state = mView.getAppState();
        if (state == 3) {
            mView.exitToStationView();
        } else if (state == 0) {
            mView.enterTrainSelection();  // enter cursor list on station indicator
        } else if (state == 1) {
            if (mView.mCursorIndex == -1) {
                mView.cycleStation();     // cycle station when on station indicator
            } else {
                mView.confirmTrainSelection();
            }
        } else if (state == 2) {
            mView.enterMapView();
        }
        return true;
    }

    function onBack() {
        mView.mLastInteractionTime = Toybox.Time.now().value();
        var state = mView.getAppState();
        if (state == 1 || state == 2) {
            mView.exitToStationView();
            return true;  // consumed — don't exit app
        }
        // State 0 and 3: exit app explicitly
        System.exit();
        return false;
    }

    function onMenu() {
        if (mView.getAppState() == 2) {
            FavouritesMenu.openTrackingMenu(mView);
        } else {
            SettingsMenu.open();
        }
        return true;
    }
}
