using Toybox.WatchUi;

class TrainTimeDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onNextPage() {  // Down button
        var state = mView.getAppState();
        if (state == 0) {
            mView.cycleMode();            // cycle modes forward
        } else if (state == 1) {
            mView.moveCursorDown();
        }
        // State 2: no-op
        return true;
    }

    function onPreviousPage() {  // Up button
        var state = mView.getAppState();
        if (state == 0) {
            mView.cycleModeReverse();     // cycle modes backward
        } else if (state == 1) {
            mView.moveCursorUp();
        }
        // State 2: no-op
        return true;
    }

    function onSelect() {
        var state = mView.getAppState();
        if (state == 0) {
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
        if (mView.getAppState() > 0) {
            mView.exitToStationView();
            return true;  // consumed — don't exit app
        }
        return false;  // State 0: exit app
    }
}
