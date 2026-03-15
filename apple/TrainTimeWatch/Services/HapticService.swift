import WatchKit

enum HapticService {
    static func shortPulse() {
        WKInterfaceDevice.current().play(.click)
    }

    static func doublePulse() {
        WKInterfaceDevice.current().play(.notification)
    }

    static func heartbeat() {
        WKInterfaceDevice.current().play(.retry)
    }

    static func platformChange() {
        WKInterfaceDevice.current().play(.directionUp)
    }
}
