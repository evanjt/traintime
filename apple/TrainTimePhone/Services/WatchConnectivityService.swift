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

    var watchName: String {
        if #available(iOS 17.0, *) {
            return session?.companionAppInstalledOnSameDevice == true ? "Apple Watch" : "Apple Watch"
        }
        return "Apple Watch"
    }

    var onApplicationContextReceived: (([String: Any]) -> Void)?

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
            // Fall back to transferUserInfo for background delivery
            session.transferUserInfo(data)
            completion(true)
        })
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        onApplicationContextReceived?(applicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
