import WidgetKit
import Foundation

struct WidgetDeparture: Codable {
    let destination: String
    let departureTimestamp: Int
    let delay: Int
    let platform: String
    let platformChanged: Bool
    let lineNumber: String

    var minutesUntil: Int {
        (departureTimestamp - Int(Date().timeIntervalSince1970)) / 60
    }

    var minutesText: String {
        let m = minutesUntil
        if m < 0 { return "gone" }
        if m == 0 { return "now" }
        return "\(m)'"
    }

    var isGone: Bool { minutesUntil < 0 }
}

struct DepartureEntry: TimelineEntry {
    let date: Date
    let stationName: String?
    let departures: [WidgetDeparture]
    let isDormant: Bool

    static func dormant(date: Date = .now, stationName: String? = nil) -> DepartureEntry {
        DepartureEntry(date: date, stationName: stationName, departures: [], isDormant: true)
    }

    static var placeholder: DepartureEntry {
        DepartureEntry(
            date: .now,
            stationName: "Bern",
            departures: [
                WidgetDeparture(destination: "Zurich HB", departureTimestamp: Int(Date().timeIntervalSince1970) + 300, delay: 0, platform: "3", platformChanged: false, lineNumber: ""),
                WidgetDeparture(destination: "Basel SBB", departureTimestamp: Int(Date().timeIntervalSince1970) + 720, delay: 2, platform: "7", platformChanged: false, lineNumber: ""),
            ],
            isDormant: false
        )
    }
}

struct FetchResult: Codable {
    let stationName: String
    let departures: [WidgetDeparture]
    let fetchTime: TimeInterval
}
