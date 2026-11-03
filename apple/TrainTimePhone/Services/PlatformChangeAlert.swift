import Foundation

/// Whether a platform switch on the tracked train banners the Live Activity.
/// Off, the card still updates to the new platform, only without an alert.
enum PlatformChangeAlert {
    static let key = "platformChangeAlert"

    static func fires(switched: Bool, _ defaults: UserDefaults = .standard) -> Bool {
        switched && defaults.object(forKey: key) as? Bool ?? true
    }
}
