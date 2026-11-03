import ActivityKit
import UserNotifications

/// The one owner of the sound every TrainTime alert asks for. With alert
/// sounds off it names a bundled silent file rather than nil: a nil sound also
/// drops the vibration, and the alert should still buzz.
enum AlertSound {
    static let key = "alertSounds"
    static let silentFile = "silence.caf"

    enum Choice { case standard, silent }

    static func choice(_ defaults: UserDefaults = .standard) -> Choice {
        defaults.object(forKey: key) as? Bool == false ? .silent : .standard
    }

    static func notificationSound(_ choice: Choice = AlertSound.choice()) -> UNNotificationSound {
        switch choice {
        case .standard: return .default
        case .silent: return UNNotificationSound(named: UNNotificationSoundName(silentFile))
        }
    }

    static func liveActivitySound(_ choice: Choice = AlertSound.choice()) -> AlertConfiguration.AlertSound {
        switch choice {
        case .standard: return .default
        case .silent: return .named(silentFile)
        }
    }
}
