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
    const PROTOCOL_VERSION = 1;

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
        Communications.transmit(data, null, new PhoneSyncListener());
    }

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
}

class PhoneSyncListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }
    function onComplete() {}
    function onError() {}
}
