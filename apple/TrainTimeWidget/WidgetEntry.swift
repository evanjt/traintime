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

struct WidgetStation: Codable {
    let id: String
    let name: String
    let departures: [WidgetDeparture]
}

struct WidgetFetchResult: Codable {
    let train: [WidgetStation]
    let bus: [WidgetStation]
    let tram: [WidgetStation]
    let special: [WidgetStation]
    let selectedModeRaw: Int
    let selectedStationIndex: Int
    let fetchTime: TimeInterval

    var selectedMode: TransportMode {
        TransportMode(rawValue: selectedModeRaw) ?? .train
    }

    var availableModes: [TransportMode] {
        var modes: [TransportMode] = []
        if !train.isEmpty { modes.append(.train) }
        if !bus.isEmpty { modes.append(.bus) }
        if !tram.isEmpty { modes.append(.tram) }
        if !special.isEmpty { modes.append(.special) }
        return modes
    }

    func stations(for mode: TransportMode) -> [WidgetStation] {
        switch mode {
        case .train: return train
        case .bus: return bus
        case .tram: return tram
        case .special: return special
        }
    }

    var currentStation: WidgetStation? {
        let stns = stations(for: selectedMode)
        guard !stns.isEmpty else { return nil }
        let idx = min(selectedStationIndex, stns.count - 1)
        return stns[idx]
    }
}

struct DepartureEntry: TimelineEntry {
    let date: Date
    let stationName: String?
    let departures: [WidgetDeparture]
    let isDormant: Bool
    let currentMode: TransportMode?
    let availableModes: [TransportMode]
    let stationIndex: Int
    let stationCount: Int

    static func dormant(date: Date = .now, stationName: String? = nil) -> DepartureEntry {
        DepartureEntry(
            date: date, stationName: stationName, departures: [], isDormant: true,
            currentMode: nil, availableModes: [], stationIndex: 0, stationCount: 0
        )
    }

    static var placeholder: DepartureEntry {
        DepartureEntry(
            date: .now,
            stationName: "Bern",
            departures: [
                WidgetDeparture(destination: "Zurich HB", departureTimestamp: Int(Date().timeIntervalSince1970) + 300, delay: 0, platform: "3", platformChanged: false, lineNumber: ""),
                WidgetDeparture(destination: "Basel SBB", departureTimestamp: Int(Date().timeIntervalSince1970) + 720, delay: 2, platform: "7", platformChanged: false, lineNumber: ""),
            ],
            isDormant: false,
            currentMode: .train,
            availableModes: [.train],
            stationIndex: 0,
            stationCount: 1
        )
    }
}
