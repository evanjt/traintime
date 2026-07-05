using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Communications;

class TrainTimeApp extends Application.AppBase {

    var mView;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        // The hello announce lives in TrainTimeView.onShow (PhoneSync.activate):
        // transmitting from onStart hangs the sim's unit-test harness.
    }

    function onStop(state) {
        // Best-effort "closing" notice for the phone link indicator. Covers exits
        // that go through the lifecycle rather than the Back-button System.exit path.
        PhoneSync.sendClosing();
    }

    function getInitialView() {
        mView = new TrainTimeView();
        return [ mView, new TrainTimeDelegate(mView) ];
    }

    // Glance: a single tile showing the nearest pinned station (no network).
    (:glance)
    function getGlanceView() {
        return [ new TrainTimeGlanceView() ];
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (mView != null) {
            mView.handlePhoneMessage(msg.data);
        }
    }

}
