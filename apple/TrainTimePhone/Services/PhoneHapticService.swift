import UIKit

enum PhoneHapticService {
    static let key = "haptics"

    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    /// The tracked trip's Buzz choice, set by the view model while that trip is
    /// on screen. Board taps follow the setting alone.
    static var tripOverride: () -> Bool? = { nil }

    /// Covers the app's own buzzes only. Notification vibration follows the
    /// system settings.
    static func isEnabled(_ defaults: UserDefaults = .standard, session: Bool? = nil) -> Bool {
        TripMute.effective(global: defaults.object(forKey: key) as? Bool ?? true, session: session)
    }

    private static var enabledNow: Bool { isEnabled(session: tripOverride()) }

    static func shortPulse() {
        guard enabledNow else { return }
        impact.impactOccurred()
    }

    static func doublePulse() {
        guard enabledNow else { return }
        notification.notificationOccurred(.warning)
    }

    static func heartbeat() {
        guard enabledNow else { return }
        heavyImpact.impactOccurred()
    }
}
