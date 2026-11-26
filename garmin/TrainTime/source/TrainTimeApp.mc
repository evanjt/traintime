using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Communications;

class TrainTimeApp extends Application.AppBase {

    var mView;

    function initialize() {
        AppBase.initialize();
    }

    // The glance runs onStart and onStop too, with only (:glance) code loaded,
    // so app-only work starts in getInitialView. The hello announce lives in
    // TrainTimeView.onShow: transmitting from here hangs the sim's test harness.
    function onStart(state) {
    }

    function onStop(state) {
        // Best-effort "closing" notice for the phone link indicator. Covers exits
        // that go through the lifecycle rather than the Back-button System.exit path.
        if (mView != null) {
            PhoneSync.sendClosing();
        }
    }

    function getInitialView() {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        ReviewPrompt.ensureFirstLaunchTimestamp();
        mView = new TrainTimeView();
        return [ mView, new TrainTimeDelegate(mView) ];
    }

    // Glance: a single tile showing the nearest pinned station (no network).
    (:glance :glanceview)
    function getGlanceView() {
        return [ new TrainTimeGlanceView() ];
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (mView != null) {
            mView.handlePhoneMessage(msg.data);
        }
    }

}
