using Toybox.WatchUi;
using Toybox.Application.Storage;

module SettingsMenu {

    function modeLabel(mode) {
        if (mode == 1) { return "Bus"; }
        if (mode == 2) { return "Tram"; }
        return "Train";
    }

    function open() {
        var menu = new WatchUi.Menu2({:title => "Settings"});

        var defaultMode = Storage.getValue("defaultMode");
        if (defaultMode == null) { defaultMode = 0; }

        menu.addItem(new WatchUi.MenuItem(
            "Default Mode",
            modeLabel(defaultMode),
            :defaultMode,
            {}
        ));
        var favCount = FavouritesManager.getTotalCount();
        if (favCount > 0) {
            menu.addItem(new WatchUi.MenuItem(
                "Favourites",
                favCount + " saved",
                :favourites,
                {}
            ));
        }
        menu.addItem(new WatchUi.MenuItem(
            "Version",
            AppVersion.VERSION,
            :version,
            {}
        ));

        WatchUi.pushView(menu, new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        if (item.getId() == :defaultMode) {
            var current = Storage.getValue("defaultMode");
            if (current == null || current == 0) {
                current = 1;
            } else if (current == 1) {
                current = 2;
            } else {
                current = 0;
            }
            Storage.setValue("defaultMode", current);
            item.setSubLabel(SettingsMenu.modeLabel(current));
        } else if (item.getId() == :favourites) {
            // Open favourites submenu
            var allFavs = FavouritesManager.getAllFavourites();
            var subMenu = new WatchUi.Menu2({:title => "Favourites"});
            for (var i = 0; i < allFavs.size(); i++) {
                var f = allFavs[i];
                subMenu.addItem(new WatchUi.MenuItem(
                    f[0] + " " + f[1],  // lineNumber + destination
                    f[2],                // stationName
                    i,
                    {}
                ));
            }
            WatchUi.pushView(subMenu, new FavouritesListDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

class FavouritesListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        // Delete the selected favourite
        var idx = item.getId() as Toybox.Lang.Number;
        var allFavs = FavouritesManager.getAllFavourites();
        if (idx >= 0 && idx < allFavs.size()) {
            var f = allFavs[idx];
            FavouritesManager.removeFavourite(f[3], f[0], f[1]);  // stationId, lineNumber, destination
        }
        // Pop back to settings
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
