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
        }
    }
}
