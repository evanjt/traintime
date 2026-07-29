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

    // Category carrying the "Send to Watch" action, registered by the AppDelegate.
    // Attached to the reminder only when a Garmin is paired, so the action surfaces
    // on the watch (over ANCS) exactly when it can do something.
    static let garminCategory = "PENDING_ROUTE_GARMIN"
    static let sendToWatchAction = "SEND_TO_WATCH"

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
        let dist = userDistanceMeters(for: route)
        return PendingRouteLogic.notifyTs(
            route, savedLeadSec: savedLeadSec, connectionLeadSec: connectionLeadSec,
            userDistanceMeters: dist,
            walkSecondsOverride: dist != nil ? routedWalkSec(for: route) : nil)
    }

    /// The reminder split into walk + buffer for the chip and resume prompt. Uses
    /// the same distance and leads as schedule, so the readout matches what fires.
    /// walkMin is nil in static mode or for a connection leg (no walk component).
    static func nextNotifyPlan(for route: PendingRoute) -> NotifyPlan? {
        let dist = userDistanceMeters(for: route)
        // In distance-aware mode, prefer the routed walk the phone measured live
        // (same MKDirections basis as tracking) over the straight-line estimate,
        // so the chip and the lead match what tracking shows on arrival.
        let routedSec = dist != nil ? routedWalkSec(for: route) : nil
        guard let notifyTs = PendingRouteLogic.notifyTs(
            route, savedLeadSec: savedLeadSec, connectionLeadSec: connectionLeadSec,
            userDistanceMeters: dist, walkSecondsOverride: routedSec) else { return nil }
        let connection = PendingRouteLogic.isConnectionLeg(route)
        let walkMin: Int?
        if connection {
            walkMin = nil
        } else if let routedSec {
            walkMin = Int((Double(routedSec) / 60).rounded())
        } else if let dist {
            walkMin = Int(GeoUtils.walkMinutes(distanceMeters: dist).rounded())
        } else {
            walkMin = nil
        }
        let bufferSec = connection ? connectionLeadSec : savedLeadSec
        return NotifyPlan(notifyTs: notifyTs, walkMin: walkMin, bufferMin: bufferSec / 60)
    }

    /// The live routed walk to the current leg's origin, measured by the phone
    /// (`PhoneViewModel.updatePendingRouteWalk`) via MKDirections and stashed here.
    /// Nil unless routed distance is on, the stored value belongs to this route,
    /// and it's fresh, so the notifier falls back to the straight-line estimate.
    private static func routedWalkSec(for route: PendingRoute) -> Int? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "useRoutedDistance"),
              defaults.string(forKey: "pendingWalkRouteId") == route.id else { return nil }
        let stamp = defaults.integer(forKey: "pendingWalkTs")
        guard stamp > 0, Int(Date().timeIntervalSince1970) - stamp < 900 else { return nil }
        let sec = defaults.integer(forKey: "pendingWalkSec")
        return sec > 0 ? sec : nil
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

    static func schedule(_ route: PendingRoute, now: Int, fromLocationUpdate: Bool = false) {
        requestAuthorizationIfNeeded()
        let dist = userDistanceMeters(for: route)
        guard let notifyTs = PendingRouteLogic.notifyTs(
            route, savedLeadSec: savedLeadSec, connectionLeadSec: connectionLeadSec,
            userDistanceMeters: dist,
            walkSecondsOverride: dist != nil ? routedWalkSec(for: route) : nil
        ), let leg = route.currentLeg else { return cancel() }
        if notifyTs <= now {
            // Inside the window. On a (re)save that means the user just saw the
            // route, so clear any stale reminder. An SLC wake landing here must
            // not clobber anything: the previously scheduled request still
            // fires, and a reminder already delivered stays on the lock screen.
            if !fromLocationUpdate { cancel() }
            return
        }

        let line = "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        let depTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(leg.depTs)))

        let content = UNMutableNotificationContent()
        let displayLine = line.isEmpty ? String(localized: "Train") : line
        content.title = String(localized: "\(displayLine) to \(route.finalDestination)")
        content.body = String(localized: "Departs \(depTime) from \(leg.originName)")
        content.sound = .default
        content.userInfo = ["deepLink": "traintime://resumeroute"]
        // Offer "Send to Watch" only when a Garmin has actually connected here at
        // least once (sticky, cached on watch refresh). The handler re-checks the
        // live link before sending.
        if UserDefaults.standard.bool(forKey: "garminEverConnected") {
            content.categoryIdentifier = garminCategory
        }

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
        notify(title: String(localized: "Test reminder"), body: String(localized: "Route reminders are working. This is a test."))
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

    // MARK: - Approach alert (background-card sessions with no saved route)

    // A board-tap "track in the background" session has no scheduled route
    // reminder, so it schedules its own one-shot "time to leave" here. Own
    // identifier so it never collides with the route reminder above. Mirrors the
    // Android FGS maybeApproachAlert (a saved route keeps using its reminder).
    private static let approachIdentifier = "approachAlert"

    /// Schedule the distance-aware "time to leave" alert: fires walk + buffer
    /// before the effective departure. No-op (and clears any prior one) when the
    /// window has already passed at schedule time.
    static func scheduleApproachAlert(_ focused: FocusedDeparture, walkSeconds: Int, now: Int) {
        cancelApproachAlert()
        requestAuthorizationIfNeeded()
        let lead = walkSeconds + savedLeadSec
        let fireIn = focused.departureTimestamp - lead - now
        guard fireIn > 0 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        let time = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(focused.departureTimestamp + focused.delay * 60)))
        let line = focused.lineNumber.isEmpty ? String(localized: "Train") : focused.lineNumber

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to leave")
        content.body = "\(line) \(focused.destination) · \(time)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(fireIn), repeats: false)
        let request = UNNotificationRequest(identifier: approachIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelApproachAlert() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [approachIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [approachIdentifier])
    }
}
