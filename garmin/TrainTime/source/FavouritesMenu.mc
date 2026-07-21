using Toybox.WatchUi;
using Toybox.System;

module FavouritesMenu {

    // Context menu for tracking mode (State 2): star toggle + remind-on-phone + settings
    function openTrackingMenu(view) {
        var menu = new WatchUi.Menu2({:title => Txt.t(Rez.Strings.OptionsTitle)});

        var stationId = view.mStationId;
        var focused = view.mFocusedTrain;
        if (stationId != null && focused != null) {
            var lineNumber = focused["line"];
            var destination = focused["dest"];
            if (lineNumber != null && destination != null) {
                var isFav = FavouritesManager.isFavourite(stationId, lineNumber, destination);
                menu.addItem(new WatchUi.MenuItem(
                    isFav ? Txt.t(Rez.Strings.Unstar) : Txt.t(Rez.Strings.Star),
                    lineNumber + " " + destination,
                    :toggleStar,
                    {}
                ));
            }
        }

        // Send the departure to the phone for a reminder. Only shown when a phone
        // is connected and we have the origin coords the phone reminder needs.
        if (System.getDeviceSettings().phoneConnected &&
            focused != null && stationId != null &&
            view.mStationLat != null && view.mStationLon != null) {
            menu.addItem(new WatchUi.MenuItem(
                Txt.t(Rez.Strings.RemindOnPhone),
                "",
                :remindPhone,
                {}
            ));
        }

        menu.addItem(new WatchUi.MenuItem(
            Txt.t(Rez.Strings.SettingsTitle),
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
                var stationName = mView.mStationName != null
                    ? mView.mStationName : Txt.t(Rez.Strings.StationLabel);
                if (lineNumber != null && destination != null) {
                    FavouritesManager.toggleFavourite(stationId, lineNumber, destination, stationName);
                    PhoneSync.sendFavourites();
                }
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :remindPhone) {
            mView.remindOnPhone();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :openSettings) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            SettingsMenu.open(mView);
        }
    }
}
