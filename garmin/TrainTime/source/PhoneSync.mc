using Toybox.Communications;
using Toybox.System;

// Outbound watch -> phone messaging over the Connect IQ phone-app channel.
// This is the Garmin analog of WCSession.updateApplicationContext (Apple) and
// WearStateSync.pushState (Android): it lets a paired phone companion mirror what
// the watch is doing. The link is optional. When no companion is listening the
// transmit fails silently, so absence of a phone is a no-op, never an error.
module PhoneSync {

    // Monotonic handshake protocol version, matched to the phone's
    // WearSync.PROTOCOL_VERSION. Stamped on hello/alive so the phone can refuse
    // Send-to-Watch against a watch too old to parse the current track command.
    // A pre-versioning watch sends no v/pv, which the phone reads as 0.4.x.
    // pv 2: saveReminder carries an id, the watch answers ping with hello and
    // consumes ackReminder (the phone only pings a pv >= 2 watch).
    const PROTOCOL_VERSION = 2;

    // Flipped on by the first real view show (TrainTimeView.onShow). The unit-test
    // harness never shows a view, and a transmit before then hangs the sim, CI
    // stalls before running a single test. Until activated every send is a no-op.
    var enabled = false;

    function activate() {
        if (enabled) { return; }
        enabled = true;
        // Announce we're up so a listening phone greens its link indicator at once.
        sendHello();
    }

    function transmit(data) {
        if (!enabled) { return; }
        if (!(Communications has :transmit)) { return; }
        // A phoneless watch can't deliver; skip rather than queue failures.
        if (!System.getDeviceSettings().phoneConnected) { return; }
        // Debug builds (the simulator) skip the actual send: a phone-app transmit
        // makes the sim poll for the Connect IQ Mobile SDK bridge over ADB and nag
        // every heartbeat. Release builds transmit for real so the phone companion
        // still learns the watch is paired.
        if (!phoneLinkAllowed()) { return; }
        Communications.transmit(data, null, new PhoneSyncListener());
    }

    (:release)
    function phoneLinkAllowed() { return true; }

    (:debug)
    function phoneLinkAllowed() { return false; }

    // The persisted default transport mode (0 train, 1 bus, 2 tram) changed in
    // settings. Matches the cross-platform "defaultMode" contract.
    function sendDefaultMode(mode) {
        transmit({ "kind" => "state", "defaultMode" => mode });
    }

    // Liveness is announced by the watch, never polled by the phone, a phone message
    // can wake a closed watch-app on Garmin, so the phone must stay silent until the
    // user explicitly opens the watch. hello on launch, alive as a periodic heartbeat,
    // bye on exit. The phone listens and colours its indicator from these.
    // Pure builder so the versioned liveness shape is unit-testable. hello/alive
    // carry the marketing version (v) and protocol version (pv); the phone reads
    // them to gate Send-to-Watch.
    function buildLiveness(kind) {
        return { "kind" => kind, "v" => AppVersion.VERSION, "pv" => PROTOCOL_VERSION };
    }

    function sendHello() {
        transmit(buildLiveness("hello"));
    }

    function sendAlive() {
        transmit(buildLiveness("alive"));
    }

    function sendClosing() {
        transmit({ "kind" => "bye" });
    }

    // Ask the phone to send its current location. Used as a GPS fallback when the
    // watch's own signal is weak or it's outside Switzerland. The phone replies
    // with an {action:"loc", lat, lon} message handled by onPhoneLocation.
    function requestLocation() {
        transmit({ "kind" => "reqLoc" });
    }

    // The watch entered tracking for a departure. Lets the phone reflect the same
    // focused train. Keys mirror the inbound track contract (line/dest/depTs/...).
    // The builder is pure so the payload shape is unit-testable.
    function buildTrackStarted(focused, stationId) {
        if (focused == null) { return null; }
        var data = {
            "kind" => "trackStarted",
            "dest" => focused["dest"],
            "depTs" => focused["depTs"],
            "line" => focused["line"],
            "delay" => focused["delay"],
            "plat" => focused["plat"],
            "platChg" => focused["platChg"]
        };
        if (focused["cat"] != null) { data["cat"] = focused["cat"]; }
        if (focused["trainNum"] != null) { data["trainNum"] = focused["trainNum"]; }
        if (focused["opRef"] != null) { data["opRef"] = focused["opRef"]; }
        if (stationId != null) { data["stId"] = stationId; }
        return data;
    }

    function sendTrackStarted(focused, stationId) {
        var data = buildTrackStarted(focused, stationId);
        if (data != null) { transmit(data); }
    }

    // Ask the phone to save the focused departure as a reminder (the reverse of
    // the phone's Send-to-Watch). Carries the origin station's id + coords so the
    // phone synthesises the same one-leg route as a board save and schedules its
    // distance-aware reminder. The id is stable across retries: the phone acks it
    // and dedupes on it. Pure builder for unit-testability.
    function buildSaveReminder(focused, stationId, stationName, lat, lon) {
        if (focused == null || stationId == null || lat == null || lon == null) { return null; }
        var data = {
            "kind" => "saveReminder",
            "id" => ReminderQueue.buildId(stationId, focused["depTs"], focused["line"]),
            "dest" => focused["dest"],
            "depTs" => focused["depTs"],
            "line" => focused["line"],
            "stId" => stationId,
            "stName" => stationName,
            "lat" => lat,
            "lon" => lon
        };
        if (focused["trainNum"] != null) { data["trainNum"] = focused["trainNum"]; }
        return data;
    }

    function sendSaveReminder(focused, stationId, stationName, lat, lon) {
        var data = buildSaveReminder(focused, stationId, stationName, lat, lon);
        if (data != null) { transmit(data); }
    }

    // Push the watch's full favourites to the phone for the outer-join sync. Sent
    // on every local star change and when the watch holds favourites the phone
    // lacks; the phone unions them (never replaces).
    function sendFavourites() {
        transmit({ "kind" => "favourites", "favs" => FavouritesManager.getFavouritesForSync() });
    }
}

class PhoneSyncListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }
    function onComplete() {}
    function onError() {}
}
