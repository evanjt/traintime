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
    }

    function onStop(state) {
    }

    function getInitialView() {
        mView = new TrainTimeView();
        return [ mView, new TrainTimeDelegate(mView) ];
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (mView != null) {
            mView.enterTrackingFromPhone(msg.data);
        }
    }

}
