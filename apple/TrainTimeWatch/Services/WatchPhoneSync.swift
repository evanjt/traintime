import Foundation
import WatchConnectivity

/// Watch → phone liveness + location requests over the WCSession message channel. The
/// Apple-ecosystem peer of the Garmin `PhoneSync.mc`: the watch announces itself so the phone
/// can colour its link indicator (hello on launch, alive heartbeat, bye on background) and can
/// ask the phone for its location when the watch GPS is weak. Sends only when reachable, so a
/// listening phone is optional and a missing one is a silent no-op.
enum WatchPhoneSync {

    private static func send(_ data: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(data, replyHandler: nil, errorHandler: { _ in })
    }

    // hello/alive carry the version handshake (v/pv) so the phone can gate
    // Send-to-Watch; bye/reqLoc need no version. While tracking, `tracking` adds
    // trk/trkLn so the phone mirrors the tracking state from the heartbeat alone —
    // trackStarted/trackEnded only make it prompt.
    private static func liveness(_ kind: String, tracking focused: FocusedDeparture?) -> [String: Any] {
        var data: [String: Any] = ["kind": kind, "v": WatchSyncProtocol.localVersionName, "pv": WatchSyncProtocol.version]
        if let focused {
            data["trk"] = focused.departureTimestamp
            data["trkLn"] = focused.lineNumber
        }
        return data
    }

    static func sendHello(tracking focused: FocusedDeparture? = nil) { send(liveness("hello", tracking: focused)) }
    static func sendAlive(tracking focused: FocusedDeparture? = nil) { send(liveness("alive", tracking: focused)) }
    static func sendBye() { send(["kind": "bye"]) }
    static func requestLocation() { send(["kind": "reqLoc"]) }

    /// Tracking stopped (manual exit or the departure left). The heartbeat would
    /// catch up within ~7 s; this flips the phone's button back immediately.
    static func sendTrackEnded() { send(["kind": "trackEnded"]) }

    /// "Yes, rate it" on the watch: watchOS has no review page, so the phone opens ours.
    /// Unlike the liveness messages this must not be dropped when the phone is unreachable,
    /// the queued userInfo transfer delivers it on the next connect instead.
    static func sendRateRequest() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let data = ["kind": "rateApp"]
        if session.isReachable {
            session.sendMessage(data, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(data)
            })
        } else {
            session.transferUserInfo(data)
        }
    }

    /// Ask the phone to save this departure as a reminder (the reverse of Send to
    /// Watch). Carries the origin station's id + coords so the phone synthesises the
    /// same one-leg route as a board save and schedules its distance-aware reminder.
    /// Like rateApp it must not be dropped when the phone is unreachable: queue it.
    static func sendSaveReminder(_ focused: FocusedDeparture, stationId: String, stationName: String, lat: Double, lon: Double) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var data: [String: Any] = [
            "kind": "saveReminder",
            "dest": focused.destination,
            "depTs": focused.departureTimestamp,
            "line": focused.lineNumber,
            "stId": stationId,
            "stName": stationName,
            "lat": lat,
            "lon": lon
        ]
        if let tn = focused.trainNumber { data["trainNum"] = tn }
        if session.isReachable {
            session.sendMessage(data, replyHandler: nil, errorHandler: { _ in session.transferUserInfo(data) })
        } else {
            session.transferUserInfo(data)
        }
    }

    /// Tracking started on the watch. Let the phone reflect the same focused train. Keys
    /// mirror the inbound track contract.
    static func sendTrackStarted(_ focused: FocusedDeparture, stationId: String?) {
        var data: [String: Any] = [
            "kind": "trackStarted",
            "dest": focused.destination,
            "depTs": focused.departureTimestamp,
            "line": focused.lineNumber,
            "delay": focused.delay,
            "plat": focused.platform,
            "platChg": focused.platformChanged,
            "cat": focused.category
        ]
        if let tn = focused.trainNumber { data["trainNum"] = tn }
        if let op = focused.operatorRef { data["opRef"] = op }
        if let stId = stationId { data["stId"] = stId }
        send(data)
    }
}
