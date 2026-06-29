import Foundation
import WatchConnectivity

class WatchConnectivityService: NSObject, WCSessionDelegate {
    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    var isReachable: Bool {
        session?.isReachable ?? false
    }

    var isPaired: Bool {
        session?.isPaired ?? false
    }

    var isWatchAppInstalled: Bool {
        session?.isWatchAppInstalled ?? false
    }

    var watchName: String {
        "Apple Watch"
    }

    var onApplicationContextReceived: (([String: Any]) -> Void)?
    /// Live messages from the watch (hello/alive/bye liveness + reqLoc), delivered over the
    /// reachable message channel. Distinct from the application-context sink, which carries
    /// persisted state (defaultMode / favourites / pinned stations).
    var onMessageReceived: (([String: Any]) -> Void)?

    func updateApplicationContext(_ context: [String: Any]) {
        try? session?.updateApplicationContext(context)
    }

    func sendMessage(_ data: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let session = session, session.isReachable else {
            completion(false)
            return
        }
        session.sendMessage(data, replyHandler: { _ in
            completion(true)
        }, errorHandler: { _ in
            completion(false)
        })
    }

    /// Mirror an action payload (track / mode / station / loc / back) to the watch. Sends
    /// live only when the watch app is reachable; otherwise drops it. We deliberately do NOT
    /// persist commands into the application context — a closed watch re-syncs on its next
    /// launch via the hello handshake, so there's no stale command to replay (and no risk of
    /// clobbering the favourites / defaultMode that share that context). Mirrors Garmin's
    /// "can't message a closed app" gate.
    func mirror(_ data: [String: Any]) {
        guard session?.isReachable == true else { return }
        session?.sendMessage(data, replyHandler: nil, errorHandler: { _ in })
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        onApplicationContextReceived?(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.onMessageReceived?(message) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { self.onMessageReceived?(message) }
        replyHandler(["status": "ok"])
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
