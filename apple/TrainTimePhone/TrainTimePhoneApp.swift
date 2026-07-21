import CoreLocation
import SwiftUI
import UserNotifications

/// Significant-location-change monitor for distance-aware route reminders. It
/// only runs while the feature is on, background tracking is on, and a route is
/// pending. Each low-power wake (cell/wifi, ~500 m) refreshes the stored
/// coordinate and reschedules the reminder off the new distance. Lives here so
/// it survives a background relaunch: AppDelegate re-arms it on launch.
final class ReminderTracker: NSObject, CLLocationManagerDelegate {
    static let shared = ReminderTracker()
    private let manager = CLLocationManager()

    /// Fired after the user resolves an authorization prompt (true = "Always"),
    /// so the view model can reassure the user when they decline all-time access.
    var onAuthorizationDecided: ((Bool) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Backgroundtracking defaults to on, so absence of the key reads as true.
    private var shouldTrack: Bool {
        let defaults = UserDefaults.standard
        let distanceAware = defaults.bool(forKey: "distanceAwareReminder")
        let background = (defaults.object(forKey: "backgroundReminderTracking") as? Bool) ?? true
        return distanceAware && background && PendingRouteStore.shared.pending != nil
    }

    func syncFromSettings() {
        guard shouldTrack else {
            manager.stopMonitoringSignificantLocationChanges()
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
        manager.startMonitoringSignificantLocationChanges()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        UserDefaults.standard.set(loc.coordinate.latitude, forKey: "lastLat")
        UserDefaults.standard.set(loc.coordinate.longitude, forKey: "lastLon")
        if let route = PendingRouteStore.shared.pending {
            PendingRouteNotifier.schedule(route, now: Int(Date().timeIntervalSince1970))
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        syncFromSettings()
        onAuthorizationDecided?(manager.authorizationStatus == .authorizedAlways)
    }
}

@main
struct TrainTimePhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Routes pending-route reminder taps back into the app as the
/// traintime://resumeroute deep link, and keeps the banner visible when the
/// notification fires while the app is foreground.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Register the "Send to Watch" action so it can surface on a paired Garmin.
        let sendToWatch = UNNotificationAction(
            identifier: PendingRouteNotifier.sendToWatchAction,
            title: String(localized: "Send to Watch"), options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: PendingRouteNotifier.garminCategory,
                actions: [sendToWatch], intentIdentifiers: [], options: [])
        ])
        // Bring up the Connect IQ bridge now so a background action launch (no
        // ViewModel) can still reach the watch.
        PhoneWatchService.shared.initialize()
        // Re-arm distance tracking on a normal or background (SLC) relaunch.
        ReminderTracker.shared.syncFromSettings()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // "Send to Watch": open the app via a deep link (Connect IQ only binds in
        // the foreground) and let the ViewModel push the route, mirroring the
        // Android path. Same mechanism as the default reminder tap below.
        if response.actionIdentifier == PendingRouteNotifier.sendToWatchAction {
            if let url = URL(string: "traintime://sendtowatch") {
                UIApplication.shared.open(url)
            }
            completionHandler()
            return
        }
        if let deepLink = response.notification.request.content.userInfo["deepLink"] as? String,
           let url = URL(string: deepLink) {
            UIApplication.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
