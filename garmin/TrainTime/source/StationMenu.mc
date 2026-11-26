using Toybox.WatchUi;

// The native list of nearby stations for the current mode a tap on the
// station name opens. Buttons keep stepping one station at a time.
(:touch)
module StationMenu {

    function open(view) {
        if (view.mStations == null || view.mStations.size() == 0) { return; }
        WatchUi.pushView(build(view), new StationMenuDelegate(view), WatchUi.SLIDE_UP);
    }

    function build(view) {
        return fill(new WatchUi.Menu2({:title => Txt.t(Rez.Strings.StationsLabel)}), view);
    }

    // One item per loaded station in board order, the walk under each and
    // the current one marked. The focus stays on the first item: moving it
    // scrolls the title out of view.
    function fill(menu, view) {
        var stations = view.mStations;
        for (var i = 0; i < stations.size(); i++) {
            var station = stations[i];
            var label = station.hasKey("label") ? station["label"] : "Station";
            var walk = WalkInfo.brief(station.hasKey("dist") && station["dist"] != null ? station["dist"] : 0);
            if (i == view.mStationIndex) {
                walk = Txt.t(Rez.Strings.ModeCurrent) + " · " + walk;
            }
            menu.addItem(new WatchUi.MenuItem(label, walk, i, {}));
        }
        return menu;
    }
}

(:touch)
class StationMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var mView;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        mView = view;
    }

    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        mView.pickStation(item.getId());
        WatchUi.requestUpdate();
    }
}
