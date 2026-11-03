import Foundation

// Per-device vibration switch, never synced between devices. On by default,
// so an unset key keeps the buzzes a fresh install has always had.
enum HapticsPreference {
    static let key = "haptics"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
