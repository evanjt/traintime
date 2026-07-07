import Foundation

/// Shared watch↔phone handshake versioning (Apple ecosystem peer of the Android
/// `WearSync` protocol constants and Garmin `PhoneSync.PROTOCOL_VERSION`). A watch
/// stamps every liveness announcement with its marketing version (`v`, for
/// user-facing copy) and this monotonic protocol version (`pv`, for gating). Bump
/// `version` only on a breaking payload change; raise `minTrackProtocol` to refuse
/// Send-to-Watch against a watch too old to parse the current track command. A
/// liveness message with no version field is a pre-versioning build: 0.4.x / pv 0.
enum WatchSyncProtocol {
    static let version = 1
    static let minTrackProtocol = 1
    static let legacyVersionName = "0.4.x"

    /// This build's marketing version, for stamping outbound liveness.
    static var localVersionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? legacyVersionName
    }
}

struct FocusedDeparture {
    let destination: String
    let departureTimestamp: Int
    let lineNumber: String
    let category: String
    let trainNumber: String?
    let operatorRef: String?
    var delay: Int
    var platform: String
    var platformChanged: Bool

    /// Seconds until departure (negative = departed)
    var secondsUntil: Int {
        departureTimestamp - Int(Date().timeIntervalSince1970)
    }

    /// Minutes until departure as a Double for tracking bar precision
    var minutesUntil: Double {
        Double(secondsUntil) / 60.0
    }

    /// Formatted countdown string matching Garmin logic
    var countdownText: String {
        let secs = secondsUntil
        if secs < -30 { return "Departed" }
        if secs < 5 { return "now" }
        let totalMin = secs / 60
        let remSec = secs % 60
        if totalMin < 3 {
            return String(format: "%d:%02d", totalMin, remSec)
        }
        return "\(totalMin) min"
    }
}
