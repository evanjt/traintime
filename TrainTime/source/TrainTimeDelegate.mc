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
            mView.enterTrainSelection();
        } else if (state == 1) {
            mView.moveCursorDown();
        }
        // State 2: no-op
        return true;
    }

    function onPreviousPage() {  // Up button
        var state = mView.getAppState();
        if (state == 0) {
            mView.nextStation();
        } else if (state == 1) {
            mView.moveCursorUp();
        }
        // State 2: no-op
        return true;
    }

    function onSelect() {
        var state = mView.getAppState();
        if (state == 0) {
            mView.cycleMode();
        } else if (state == 1) {
            mView.confirmTrainSelection();
        }
        // State 2: no-op
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
