import CoreLocation
import Foundation
import UserNotifications

/// The scheduled reminder split into its parts, for the in-app readout. walkMin
/// is nil outside distance-aware mode (nothing to break out); bufferMin is the
/// user's chosen lead. Lets the chip colour the calculated walk time apart from
/// the fixed buffer.
struct NotifyPlan {
    let notifyTs: Int
    let walkMin: Int?
    let bufferMin: Int
}

/// Schedules the "your train leaves soon" heads-up for a queued shared
/// route. Port of android app notify/PendingRouteNotifier.kt, using a
/// calendar-triggered local notification (delivered by the OS even after the
/// app is killed). Tap deep-links traintime://resumeroute.
enum PendingRouteNotifier {
    // One reminder at a time, so a constant identifier: adding replaces any
    // existing pending request atomically (the analog of Android's
    // enqueueUniqueWork(REPLACE)) and cancel removes exactly it.
    private static let identifier = "pendingRoute"

    /// Saved-route lead in seconds, from the user's Settings choice (minutes).
    private static var savedLeadSec: Int {
        let minutes = UserDefaults.standard.integer(forKey: "routeReminderLeadMinutes")
        return (minutes > 0 ? minutes : 15) * 60
    }

    /// Next-connection lead in seconds, set independently of the saved-route
    /// lead. Defaults to 3 min when unset.
    private static var connectionLeadSec: Int {
        let minutes = UserDefaults.standard.integer(forKey: "connectionReminderLeadMinutes")
        return (minutes > 0 ? minutes : 3) * 60
    }

    private static var distanceAware: Bool {
        UserDefaults.standard.bool(forKey: "distanceAwareReminder")
    }

    /// Absolute epoch-second the reminder is set to fire for this route, using
    /// the same rule as schedule. For the in-app "notified in X min" readout.
    static func nextNotifyTs(for route: PendingRoute) -> Int? {
        PendingRouteLogic.notifyTs(
            route, savedLeadSec: savedLeadSec, connectionLeadSec: connectionLeadSec,
            userDistanceMeters: userDistanceMeters(for: route))
    }

    /// The reminder split into walk + buffer for the chip and resume prompt. Uses
    /// the same distance and leads as schedule, so the readout matches what fires.
    /// walkMin is nil in static mode or for a connection leg (no walk component).
    static func nextNotifyPlan(for route: PendingRoute) -> NotifyPlan? {
        let dist = userDistanceMeters(for: route)
        guard let notifyTs = PendingRouteLogic.notifyTs(
            route, savedLeadSec: savedLeadSec, connectionLeadSec: connectionLeadSec,
            userDistanceMeters: dist) else { return nil }
        let connection = PendingRouteLogic.isConnectionLeg(route)
        let walkMin: Int? = (dist != nil && !connection)
            ? Int(GeoUtils.walkMinutes(distanceMeters: dist!).rounded())
            : nil
        let bufferSec = connection ? connectionLeadSec : savedLeadSec
        return NotifyPlan(notifyTs: notifyTs, walkMin: walkMin, bufferMin: bufferSec / 60)
    }

    /// Straight-line distance from the last known location to the current leg's
    /// origin, only in distance-aware mode. Nil (static lead) when off, no leg,
    /// or no stored coordinate.
    private static func userDistanceMeters(for route: PendingRoute) -> Double? {
        guard distanceAware, let leg = route.currentLeg,
              let originLat = leg.originLat, let originLon = leg.originLon else { return nil }
        let lat = UserDefaults.standard.double(forKey: "lastLat")
        let lon = UserDefaults.standard.double(forKey: "lastLon")
        guard lat != 0, lon != 0 else { return nil }
        return GeoUtils.haversineDistance(
            from: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            to: CLLocationCoordinate2D(latitude: originLat, longitude: originLon))
    }

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
        guard let notifyTs = PendingRouteLogic.notifyTs(
            route, savedLeadSec: savedLeadSec, connectionLeadSec: connectionLeadSec,
            userDistanceMeters: userDistanceMeters(for: route)
        ), notifyTs > now, let leg = route.currentLeg else { return cancel() }

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
        // Constant identifier: replaces any prior pending reminder atomically.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Fires in a few seconds so the user can confirm permission + delivery
    /// without waiting for a real departure. Own identifier so it never
    /// disturbs a scheduled reminder.
    static func sendTest() {
        notify(title: "Test reminder", body: "Route reminders are working. This is a test.")
    }

    /// Posts a short-delay notification in the reminder channel. Used by the test
    /// buttons (plain + distance readout). Own identifier so it never disturbs a
    /// scheduled reminder.
    static func notify(title: String, body: String) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifier)-test", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
