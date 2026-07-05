import Foundation

// Decides whether to auto-prompt for a review. Mirrors the Android ReviewGate
// so the ask behaves identically on every platform: enough tracking sessions,
// an install old enough to have formed an opinion, no active snooze, no
// permanent opt-out, and at most once per release. Pure for unit testing.
enum ReviewGate {
    static let trackThreshold = 3
    static let minAge: TimeInterval = 3 * 24 * 60 * 60
    static let snooze: TimeInterval = 14 * 24 * 60 * 60

    static func shouldPrompt(
        trackCount: Int,
        promptedVersion: String,
        currentVersion: String,
        firstLaunch: Date?,
        snoozeUntil: Date?,
        optedOut: Bool,
        now: Date
    ) -> Bool {
        guard !optedOut,
              trackCount >= trackThreshold,
              let firstLaunch, now.timeIntervalSince(firstLaunch) >= minAge,
              now >= (snoozeUntil ?? .distantPast),
              promptedVersion != currentVersion
        else { return false }
        return true
    }
}

// UserDefaults wrapper for the gate's keys. Review state is deliberately
// per-device (never synced): each device rates its own store.
struct ReviewStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var trackCount: Int { defaults.integer(forKey: "reviewTrackCount") }
    var promptedVersion: String { defaults.string(forKey: "reviewPromptedVersion") ?? "" }
    var optedOut: Bool { defaults.bool(forKey: "reviewOptOut") }

    var firstLaunch: Date? {
        let ts = defaults.double(forKey: "firstLaunchTs")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    var snoozeUntil: Date? {
        let ts = defaults.double(forKey: "reviewSnoozeUntil")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func ensureFirstLaunchTimestamp(now: Date = Date()) {
        if defaults.double(forKey: "firstLaunchTs") <= 0 {
            defaults.set(now.timeIntervalSince1970, forKey: "firstLaunchTs")
        }
    }

    func incrementTrackCount() {
        defaults.set(trackCount + 1, forKey: "reviewTrackCount")
    }

    func markPrompted(version: String) {
        defaults.set(version, forKey: "reviewPromptedVersion")
    }

    func snooze(now: Date = Date()) {
        defaults.set(now.addingTimeInterval(ReviewGate.snooze).timeIntervalSince1970, forKey: "reviewSnoozeUntil")
    }

    func optOut() {
        defaults.set(true, forKey: "reviewOptOut")
    }

    // The gate, fed from this store.
    func shouldPrompt(now: Date = Date()) -> Bool {
        ReviewGate.shouldPrompt(
            trackCount: trackCount,
            promptedVersion: promptedVersion,
            currentVersion: Self.currentVersion,
            firstLaunch: firstLaunch,
            snoozeUntil: snoozeUntil,
            optedOut: optedOut,
            now: now
        )
    }
}
