import Foundation

struct Departure: Identifiable {
    let id = UUID()
    let destination: String
    let minutesUntil: Int
    let delay: Int
    let platform: String
    let platformChanged: Bool

    var isGone: Bool { minutesUntil < 0 }

    var minutesText: String {
        if isGone { return "gone" }
        if minutesUntil == 0 { return "now" }
        return "\(minutesUntil)'"
    }
}
