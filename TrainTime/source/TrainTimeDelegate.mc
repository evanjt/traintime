using Toybox.WatchUi;

class TrainTimeDelegate extends WatchUi.BehaviorDelegate {

    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onNextPage() {
        mView.nextStation();
        return true;
    }

    function onPreviousPage() {
        mView.previousStation();
        return true;
    }

    function onSelect() {
        return true;
    }

    function onBack() {
        return false;
    }
}
