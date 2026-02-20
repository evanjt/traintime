using Toybox.Application;
using Toybox.WatchUi;

class TrainTimeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        var view = new TrainTimeView();
        return [ view, new TrainTimeDelegate(view) ];
    }

}
