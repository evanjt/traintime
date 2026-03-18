import SwiftUI
import UserNotifications
import WatchConnectivity

@main
struct TrainTimeWatchApp: App {
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .backgroundTask(.watchConnectivity) {
            // Woken by transferUserInfo from iOS — WCSession delegate
            // methods fire automatically to process pending data
        }
    }
}
