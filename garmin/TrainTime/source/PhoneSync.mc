using Toybox.Communications;

// Outbound watch -> phone messaging over the Connect IQ phone-app channel.
// This is the Garmin analog of WCSession.updateApplicationContext (Apple) and
// WearStateSync.pushState (Android): it lets a paired phone companion mirror what
// the watch is doing. The link is optional. When no companion is listening the
// transmit fails silently, so absence of a phone is a no-op, never an error.
module PhoneSync {

    function transmit(data) {
        if (Communications has :transmit) {
            Communications.transmit(data, null, new PhoneSyncListener());
        }
    }

    // The persisted default transport mode (0 train, 1 bus, 2 tram) changed in
    // settings. Matches the cross-platform "defaultMode" contract.
    function sendDefaultMode(mode) {
        transmit({ "kind" => "state", "defaultMode" => mode });
    }

    // The watch entered tracking for a departure. Lets the phone reflect the same
    // focused train. Keys mirror the inbound track contract (line/dest/depTs/...).
    function sendTrackStarted(focused, stationId) {
        if (focused == null) { return; }
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
        transmit(data);
    }
}

class PhoneSyncListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }
    function onComplete() {}
    function onError() {}
}
