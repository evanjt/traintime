using Toybox.WatchUi;
using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

module SettingsMenu {

    // openWebPage surfaces this on the paired phone via Garmin Connect Mobile.
    // There is no on-device review API, so the listing opens in the store there.
    const STORE_URL = "https://apps.garmin.com/apps/c70bbfae-846a-4d00-9e96-d485217035fb";

    function modeLabel(mode) {
        if (mode == 1) { return Txt.t(Rez.Strings.ModeBus); }
        if (mode == 2) { return Txt.t(Rez.Strings.ModeTram); }
        return Txt.t(Rez.Strings.ModeTrain);
    }

    function open(view) {
        var menu = new WatchUi.Menu2({:title => Txt.t(Rez.Strings.SettingsTitle)});

        // Phone link status. The channel the phone uses to send departures here.
        // Connected only means Bluetooth to Garmin Connect Mobile; an unacked
        // reminder in the outbox is worth surfacing alongside.
        var phoneConnected = System.getDeviceSettings().phoneConnected;
        ReminderQueue.prune(Time.now().value());
        var phoneLabel = phoneConnected
            ? Txt.t(Rez.Strings.Connected) : Txt.t(Rez.Strings.NotConnected);
        if (ReminderQueue.hasPending()) {
            phoneLabel = Lang.format(Txt.t(Rez.Strings.ReminderWaitingFmt), [phoneLabel]);
        }
        menu.addItem(new WatchUi.MenuItem(
            Txt.t(Rez.Strings.Phone),
            phoneLabel,
            :phoneStatus,
            {}
        ));

        // Pin/unpin the currently shown station.
        if (view != null && view.mStationId != null) {
            var pinned = MyStationsManager.isPinned(view.mStationId);
            menu.addItem(new WatchUi.MenuItem(
                pinned ? Txt.t(Rez.Strings.UnpinStation) : Txt.t(Rez.Strings.PinStation),
                view.mStationName != null ? view.mStationName : "",
                :pinStation,
                {}
            ));
        }

        var defaultMode = Storage.getValue("defaultMode");
        if (defaultMode == null) { defaultMode = 0; }

        menu.addItem(new WatchUi.MenuItem(
            Txt.t(Rez.Strings.DefaultMode),
            modeLabel(defaultMode),
            :defaultMode,
            {}
        ));

        // Quick launch: pinned stations and favourite trains.
        if (MyStationsManager.getCount() > 0 || FavouritesManager.getTotalCount() > 0) {
            menu.addItem(new WatchUi.MenuItem(
                Txt.t(Rez.Strings.QuickLaunch),
                Lang.format(Txt.t(Rez.Strings.PinnedCountFmt), [MyStationsManager.getCount()]),
                :quickLaunch,
                {}
            ));
        }

        var favCount = FavouritesManager.getTotalCount();
        if (favCount > 0) {
            menu.addItem(new WatchUi.MenuItem(
                Txt.t(Rez.Strings.Favourites),
                Lang.format(Txt.t(Rez.Strings.SavedCountFmt), [favCount]),
                :favourites,
                {}
            ));
        }
        menu.addItem(new WatchUi.MenuItem(
            Txt.t(Rez.Strings.RateApp),
            Txt.t(Rez.Strings.OpensOnPhone),
            :rate,
            {}
        ));
        menu.addItem(new WatchUi.MenuItem(
            Txt.t(Rez.Strings.Version),
            AppVersion.VERSION,
            :version,
            {}
        ));
        // Data attribution, matching the Apple/Wear settings footers.
        menu.addItem(new WatchUi.MenuItem(
            Txt.t(Rez.Strings.DataLabel),
            "opentransportdata.swiss",
            :dataSource,
            {}
        ));

        WatchUi.pushView(menu, new SettingsMenuDelegate(view), WatchUi.SLIDE_UP);
    }

    function openQuickLaunch(view) {
        var menu = new WatchUi.Menu2({:title => Txt.t(Rez.Strings.QuickLaunch)});
        var pinned = MyStationsManager.getMyStations();
        for (var i = 0; i < pinned.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(
                pinned[i]["name"],
                Txt.t(Rez.Strings.StationLabel),
                i,
                {}
            ));
        }
        var favs = FavouritesManager.getAllFavourites();
        for (var i = 0; i < favs.size(); i++) {
            var f = favs[i];
            menu.addItem(new WatchUi.MenuItem(
                f[0] + " " + f[1],   // lineNumber + destination
                f[2],                 // stationName
                pinned.size() + i,
                {}
            ));
        }
        WatchUi.pushView(menu, new QuickLaunchDelegate(view, pinned, favs), WatchUi.SLIDE_LEFT);
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var mView;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        mView = view;
    }

    function onSelect(item) {
        if (item.getId() == :pinStation) {
            if (mView != null) {
                mView.togglePinCurrentStation();
                var pinned = MyStationsManager.isPinned(mView.mStationId);
                item.setLabel(pinned
                    ? Txt.t(Rez.Strings.UnpinStation) : Txt.t(Rez.Strings.PinStation));
            }
        } else if (item.getId() == :defaultMode) {
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
            PhoneSync.sendDefaultMode(current);
        } else if (item.getId() == :quickLaunch) {
            SettingsMenu.openQuickLaunch(mView);
        } else if (item.getId() == :favourites) {
            // Open favourites submenu
            var allFavs = FavouritesManager.getAllFavourites();
            var subMenu = new WatchUi.Menu2({:title => Txt.t(Rez.Strings.Favourites)});
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
        } else if (item.getId() == :rate) {
            // Opens the Connect IQ Store listing on the paired phone.
            if (Communications has :openWebPage) {
                Communications.openWebPage(SettingsMenu.STORE_URL, null, null);
            }
        }
    }
}

// Quick-launch a pinned station (direct fetch) or a favourite train (tracking).
class QuickLaunchDelegate extends WatchUi.Menu2InputDelegate {

    private var mView;
    private var mPinned;
    private var mFavs;

    function initialize(view, pinned, favs) {
        Menu2InputDelegate.initialize();
        mView = view;
        mPinned = pinned;
        mFavs = favs;
    }

    function onSelect(item) {
        var idx = item.getId() as Toybox.Lang.Number;
        if (mView == null) { return; }
        // Pop the quick-launch and settings menus back to the main view first.
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        if (idx < mPinned.size()) {
            var s = mPinned[idx];
            mView.launchStation(s["id"], s["name"], s["lat"], s["lon"]);
        } else {
            var f = mFavs[idx - mPinned.size()];
            // f = [lineNumber, destination, stationName, stationId]
            mView.enterTrackingForFavourite(f[3], f[2], f[0], f[1]);
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
            PhoneSync.sendFavourites();
        }
        // Pop back to settings
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
