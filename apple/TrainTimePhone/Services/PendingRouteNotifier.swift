import Foundation
import UserNotifications

/// Schedules the "your train leaves soon" heads-up for a queued shared
/// route. Port of android app notify/PendingRouteNotifier.kt, using a
/// calendar-triggered local notification (delivered by the OS even after the
/// app is killed). Tap deep-links traintime://resumeroute.
enum PendingRouteNotifier {
    private static let identifierPrefix = "pendingRoute"

    /// Contextual ask the first time anything schedules a reminder. Every
    /// schedule call happens app-foreground (share deep link, leg toggle,
    /// tracking hand-off), so the system prompt is always legal. Denial is
    /// fine: the chip and resume prompt work without the reminder. iOS
    /// evaluates authorisation at delivery, so a request racing the schedule
    /// still delivers once granted.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func schedule(_ route: PendingRoute, now: Int) {
        requestAuthorizationIfNeeded()
        cancel()
        guard let notifyTs = PendingRouteLogic.notifyTs(route), notifyTs > now,
              let leg = route.currentLeg else { return }

        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        let depTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs)))

        let content = UNMutableNotificationContent()
        content.title = "\(line.isEmpty ? "Train" : line) to \(route.finalDestination)"
        content.body = "Departs \(depTime) from \(leg.originName)"
        content.sound = .default
        content.userInfo = ["deepLink": "traintime://resumeroute"]

        let fireDate = Date(timeIntervalSince1970: TimeInterval(notifyTs))
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-\(route.id)-\(route.cursor)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { notifications in
            let ids = notifications.map(\.request.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}
