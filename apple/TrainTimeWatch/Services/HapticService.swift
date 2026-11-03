import WatchKit

enum HapticService {
    static func shortPulse() {
        play(.click)
    }

    static func doublePulse() {
        play(.notification)
    }

    static func heartbeat() {
        play(.retry)
    }

    static func platformChange() {
        play(.directionUp)
    }

    private static func play(_ type: WKHapticType) {
        guard HapticsPreference.isEnabled() else { return }
        WKInterfaceDevice.current().play(type)
    }
}
