import Foundation

struct FocusedDeparture {
    let destination: String
    let departureTimestamp: Int
    var delay: Int
    var platform: String
    var platformChanged: Bool

    /// Seconds until departure (negative = departed)
    var secondsUntil: Int {
        departureTimestamp - Int(Date().timeIntervalSince1970)
    }

    /// Minutes until departure as a Double for tracking bar precision
    var minutesUntil: Double {
        Double(secondsUntil) / 60.0
    }

    /// Formatted countdown string matching Garmin logic
    var countdownText: String {
        let secs = secondsUntil
        if secs < -30 { return "Departed" }
        if secs < 5 { return "now" }
        let totalMin = secs / 60
        let remSec = secs % 60
        if totalMin < 3 {
            return String(format: "%d:%02d", totalMin, remSec)
        }
        return "\(totalMin) min"
    }
}
