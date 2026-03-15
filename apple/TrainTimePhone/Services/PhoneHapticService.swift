import UIKit

enum PhoneHapticService {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    static func shortPulse() {
        impact.impactOccurred()
    }

    static func doublePulse() {
        notification.notificationOccurred(.warning)
    }

    static func heartbeat() {
        heavyImpact.impactOccurred()
    }

    static func platformChange() {
        notification.notificationOccurred(.error)
    }
}
