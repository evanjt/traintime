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

    static func sendHello() { send(["kind": "hello"]) }
    static func sendAlive() { send(["kind": "alive"]) }
    static func sendBye() { send(["kind": "bye"]) }
    static func requestLocation() { send(["kind": "reqLoc"]) }

    /// Tracking started on the watch — let the phone reflect the same focused train. Keys
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
