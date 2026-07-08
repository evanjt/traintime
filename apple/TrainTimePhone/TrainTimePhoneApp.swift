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
            title: "Send to Watch", options: [])
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
        // "Send to Watch": wake the Garmin app and push the saved route into
        // tracking, silently, without opening the phone.
        if response.actionIdentifier == PendingRouteNotifier.sendToWatchAction {
            sendPendingRouteToWatch(completion: completionHandler)
            return
        }
        if let deepLink = response.notification.request.content.userInfo["deepLink"] as? String,
           let url = URL(string: deepLink) {
            UIApplication.shared.open(url)
        }
        completionHandler()
    }

    /// Send the current saved route to a paired Garmin. The watch app must finish
    /// launching before it can receive the track, so we open it, let device status
    /// settle, then transmit twice over a short window (silent drop if it never
    /// wakes). A background-task assertion keeps us alive through the window.
    private func sendPendingRouteToWatch(completion: @escaping () -> Void) {
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "SendToWatch")
        let finish: () -> Void = {
            completion()
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }

        let now = Int(Date().timeIntervalSince1970)
        guard let route = PendingRouteStore.shared.pending
                .flatMap({ PendingRouteLogic.normalize($0, now: now) }),
              let leg = route.currentLeg else { return finish() }

        let service = PhoneWatchService.shared
        service.initialize()
        guard service.hasKnownGarmin else { return finish() }
        let payload = PhoneWatchService.GarminPayload.track(
            leg: leg, finalDestination: route.finalDestination)

        // Let device statuses land, then wake the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            service.refreshConnectedWatches()
            service.openGarminApp()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            service.sendToGarminWatches(payload)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            service.sendToGarminWatches(payload)
            finish()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
