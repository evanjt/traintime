using Toybox.WatchUi;

module FavouritesMenu {

    // Context menu for tracking mode (State 2) — star toggle + settings
    function openTrackingMenu(view) {
        var menu = new WatchUi.Menu2({:title => "Options"});

        var stationId = view.mStationId;
        var focused = view.mFocusedTrain;
        if (stationId != null && focused != null) {
            var lineNumber = focused["line"];
            var destination = focused["dest"];
            if (lineNumber != null && destination != null) {
                var isFav = FavouritesManager.isFavourite(stationId, lineNumber, destination);
                menu.addItem(new WatchUi.MenuItem(
                    isFav ? "Unstar" : "Star",
                    lineNumber + " " + destination,
                    :toggleStar,
                    {}
                ));
            }
        }

        menu.addItem(new WatchUi.MenuItem(
            "Settings",
            "",
            :openSettings,
            {}
        ));

        WatchUi.pushView(menu, new FavouritesMenuDelegate(view), WatchUi.SLIDE_UP);
    }
}

class FavouritesMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var mView;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        mView = view;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :toggleStar) {
            var stationId = mView.mStationId;
            var focused = mView.mFocusedTrain;
            if (stationId != null && focused != null) {
                var lineNumber = focused["line"];
                var destination = focused["dest"];
                var stationName = mView.mStationName != null ? mView.mStationName : "Station";
                if (lineNumber != null && destination != null) {
                    FavouritesManager.toggleFavourite(stationId, lineNumber, destination, stationName);
                }
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :openSettings) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            SettingsMenu.open();
        }
    }
}
