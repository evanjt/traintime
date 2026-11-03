import UIKit

enum PhoneHapticService {
    static let key = "haptics"

    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    /// Covers the app's own buzzes only. Notification vibration follows the
    /// system settings.
    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func shortPulse() {
        guard isEnabled() else { return }
        impact.impactOccurred()
    }

    static func doublePulse() {
        guard isEnabled() else { return }
        notification.notificationOccurred(.warning)
    }

    static func heartbeat() {
        guard isEnabled() else { return }
        heavyImpact.impactOccurred()
    }
}
