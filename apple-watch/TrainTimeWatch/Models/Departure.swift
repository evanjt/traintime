import Foundation

struct Departure: Identifiable {
    let id = UUID()
    let destination: String
    let minutesUntil: Int
    let departureTimestamp: Int?
    let delay: Int
    let platform: String
    let platformChanged: Bool

    var isGone: Bool { minutesUntil < 0 }

    /// Seconds until departure (more precise than minutesUntil for tracking)
    var secondsUntil: Int? {
        guard let ts = departureTimestamp else { return nil }
        return ts - Int(Date().timeIntervalSince1970)
    }

    var minutesText: String {
        if isGone { return "gone" }
        if minutesUntil == 0 { return "now" }
        return "\(minutesUntil)'"
    }
}
