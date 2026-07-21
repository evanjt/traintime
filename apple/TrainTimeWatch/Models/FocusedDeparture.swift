import Foundation

/// Shared watch↔phone handshake versioning (Apple ecosystem peer of the Android
/// `WearSync` constants and Garmin `PhoneSync.PROTOCOL_VERSION`). A watch stamps
/// every liveness announcement with its marketing version (`v`, for gating +
/// user-facing copy) and a monotonic protocol version (`pv`, reserved for a
/// future breaking-payload gate). A liveness message with no version field is a
/// pre-versioning build, read as the legacy version 0.4.x.
enum WatchSyncProtocol {
    // pv 2: hello/alive carry the tracked departure (trk/trkLn) while tracking,
    // and trackEnded is sent when tracking stops. A phone seeing pv >= 2 treats
    // a heartbeat without trk as "not tracking".
    static let version = 2
    static let legacyVersionName = "0.4.x"

    /// The only current constraint: the sync features require a watch reporting
    /// 0.5.x or higher. Major.minor only, so "0.5.x" and "0.5.1" both satisfy it.
    static let minSyncMajor = 0
    static let minSyncMinor = 5

    /// This build's marketing version, for stamping outbound liveness.
    static var localVersionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? legacyVersionName
    }

    /// True when a watch reporting this version is new enough for the sync
    /// features. Nil / unparseable (a watch that sent no version) fails.
    static func meetsSyncMinimum(_ version: String?) -> Bool {
        guard let version, let mm = majorMinor(version) else { return false }
        return mm.major > minSyncMajor || (mm.major == minSyncMajor && mm.minor >= minSyncMinor)
    }

    private static func majorMinor(_ version: String) -> (major: Int, minor: Int)? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    /// Gate for the foreground ping to a Garmin watch. A phone message can wake a
    /// closed Garmin watch-app, so only ping one that speaks pv 2 (treats ping as
    /// such), hasn't said bye since its last alive, and was heard from recently.
    static let garminPingWindow: TimeInterval = 30

    static func shouldPingGarmin(lastAlive: Date, lastBye: Date, now: Date, pv: Int) -> Bool {
        pv >= 2 && lastAlive > lastBye && now.timeIntervalSince(lastAlive) <= garminPingWindow
    }
}

struct FocusedDeparture {
    // var: a protected route leg's terminus is upgraded from the live board match.
    var destination: String
    let departureTimestamp: Int
    let lineNumber: String
    let category: String
    let trainNumber: String?
    let operatorRef: String?
    var delay: Int
    var platform: String
    var platformChanged: Bool
    /// Set only when tracking a saved route: the route's final destination, so the
    /// header keeps the train's own terminus while a "Tracking route to X" subtext
    /// carries where the journey actually ends. Nil for board taps.
    var routeDestination: String? = nil

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
