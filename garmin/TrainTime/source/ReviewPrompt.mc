using Toybox.WatchUi;
using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Time;

// Timed review ask, mirroring the phone/Wear gate: enough tracked departures,
// an install old enough to have formed an opinion, no active snooze, no
// permanent opt-out, once per release. Shown on the tracking -> station-view
// exit rather than at tracking entry so it never covers a live countdown.
module ReviewPrompt {

    const TRACK_THRESHOLD = 3;
    const MIN_AGE_SEC = 3 * 24 * 60 * 60;
    const SNOOZE_SEC = 14 * 24 * 60 * 60;

    // Pure so LogicTest can drive it without Storage. Timestamps in seconds.
    function shouldPrompt(trackCount, promptedVersion, currentVersion, firstLaunchTs, snoozeUntil, optedOut, now) {
        if (optedOut) { return false; }
        if (trackCount < TRACK_THRESHOLD) { return false; }
        if (firstLaunchTs == null || firstLaunchTs <= 0) { return false; }
        if (now - firstLaunchTs < MIN_AGE_SEC) { return false; }
        if (now < snoozeUntil) { return false; }
        if (promptedVersion != null && promptedVersion.equals(currentVersion)) { return false; }
        return true;
    }

    function ensureFirstLaunchTimestamp() {
        var ts = Storage.getValue("reviewFirstLaunchTs");
        if (ts == null || ts <= 0) {
            Storage.setValue("reviewFirstLaunchTs", Time.now().value());
        }
    }

    function incrementTrackCount() {
        var c = Storage.getValue("reviewTrackCount");
        Storage.setValue("reviewTrackCount", (c == null ? 0 : c) + 1);
    }

    function maybeShow() {
        var count = Storage.getValue("reviewTrackCount");
        var snooze = Storage.getValue("reviewSnoozeUntil");
        if (!shouldPrompt(
                count == null ? 0 : count,
                Storage.getValue("reviewPromptedVersion"),
                AppVersion.VERSION,
                Storage.getValue("reviewFirstLaunchTs"),
                snooze == null ? 0 : snooze,
                Storage.getValue("reviewOptOut") == true,
                Time.now().value())) {
            return;
        }
        // Shown counts as asked for this version, whatever option follows.
        Storage.setValue("reviewPromptedVersion", AppVersion.VERSION);
        var menu = new WatchUi.Menu2({:title => "Enjoying TrainTime?"});
        menu.addItem(new WatchUi.MenuItem("Yes, rate it", "Opens on your phone", :rate, {}));
        menu.addItem(new WatchUi.MenuItem("Not now", null, :notNow, {}));
        menu.addItem(new WatchUi.MenuItem("Don't ask again", null, :never, {}));
        WatchUi.pushView(menu, new ReviewPromptDelegate(), WatchUi.SLIDE_UP);
    }
}

class ReviewPromptDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        if (item.getId() == :rate) {
            // Opens the Connect IQ Store listing on the paired phone.
            if (Communications has :openWebPage) {
                Communications.openWebPage(SettingsMenu.STORE_URL, null, null);
            }
        } else if (item.getId() == :notNow) {
            Storage.setValue("reviewSnoozeUntil", Time.now().value() + ReviewPrompt.SNOOZE_SEC);
        } else if (item.getId() == :never) {
            Storage.setValue("reviewOptOut", true);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() {
        // Backing out counts as "Not now".
        Storage.setValue("reviewSnoozeUntil", Time.now().value() + ReviewPrompt.SNOOZE_SEC);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
