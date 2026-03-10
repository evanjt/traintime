using Toybox.WatchUi;

class TrainTimeMapDelegate extends WatchUi.BehaviorDelegate {
    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onBack() {
        mView.exitMapView();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
