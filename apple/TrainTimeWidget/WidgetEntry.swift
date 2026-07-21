import WidgetKit
import Foundation

struct WidgetDeparture: Codable {
    let destination: String
    let departureTimestamp: Int
    let delay: Int
    let platform: String
    let platformChanged: Bool
    let lineNumber: String

    // WidgetKit pre-renders every timeline entry at creation time, so countdowns must be
    // computed against the entry's date, not Date(), or all future entries freeze.
    func minutesUntil(at date: Date) -> Int {
        (departureTimestamp - Int(date.timeIntervalSince1970)) / 60
    }

    func minutesText(at date: Date) -> String {
        let m = minutesUntil(at: date)
        if m < 0 { return String(localized: "gone") }
        if m == 0 { return String(localized: "now") }
        return "\(m)'"
    }

    func isGone(at date: Date) -> Bool { minutesUntil(at: date) < 0 }

    /// Absolute clock time "HH:mm", shown in the dormant view, where a stale minute count would mislead.
    var clockTimeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(departureTimestamp)))
    }

    var favKey: String { "\(lineNumber)|\(destination)" }
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

/// App Group cache shared by the widget and the phone app. The single key + codec live here
/// so both processes agree on the format; the phone seeds it on background, the widget reads it.
extension WidgetFetchResult {
    static let cacheKey = "widget_fetch_result_v3"

    static func loadCached() -> WidgetFetchResult? {
        guard let data = SharedDefaults.store.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetFetchResult.self, from: data)
    }

    func cache() {
        if let data = try? JSONEncoder().encode(self) {
            SharedDefaults.store.set(data, forKey: WidgetFetchResult.cacheKey)
        }
    }
}

/// Favourite extraction for the widget. Lives here (not in FavouritesStore) because it
/// operates on WidgetDeparture, which is not compiled into the watch target.
enum WidgetFavourites {
    /// One not-yet-gone departure per station favourite, sorted by time: the block at the top.
    static func block(in departures: [WidgetDeparture], favourites: [Favourite], at date: Date) -> [WidgetDeparture] {
        guard !favourites.isEmpty else { return [] }
        var result: [WidgetDeparture] = []
        for fav in favourites {
            if let match = departures.first(where: {
                $0.lineNumber == fav.lineNumber && $0.destination == fav.destination && !$0.isGone(at: date)
            }) {
                result.append(match)
            }
        }
        return result.sorted { $0.departureTimestamp < $1.departureTimestamp }
    }

    static func keys(_ favourites: [Favourite]) -> Set<String> {
        Set(favourites.map { "\($0.lineNumber)|\($0.destination)" })
    }
}

struct DepartureEntry: TimelineEntry {
    let date: Date
    let stationName: String?
    let departures: [WidgetDeparture]
    let favouriteDepartures: [WidgetDeparture]
    let favouriteKeys: Set<String>
    let asOf: Date?
    let isDormant: Bool
    let currentMode: TransportMode?
    let availableModes: [TransportMode]
    let stationIndex: Int
    let stationCount: Int
    let hideFavouritesBlock: Bool
    let outsideSwitzerland: Bool

    static func dormant(date: Date = .now, stationName: String? = nil) -> DepartureEntry {
        DepartureEntry(
            date: date, stationName: stationName, departures: [], favouriteDepartures: [],
            favouriteKeys: [], asOf: nil, isDormant: true,
            currentMode: nil, availableModes: [], stationIndex: 0, stationCount: 0,
            hideFavouritesBlock: false, outsideSwitzerland: false
        )
    }

    /// Build an entry from cache for a given render date, flagging favourites per that date.
    /// Used for both active and stale-dormant entries (the dormant view ignores the switcher).
    static func make(date: Date, result: WidgetFetchResult, favourites: [Favourite], isDormant: Bool, hideFavouritesBlock: Bool, outsideSwitzerland: Bool) -> DepartureEntry {
        let station = result.currentStation
        let deps = station?.departures ?? []
        let stns = result.stations(for: result.selectedMode)
        return DepartureEntry(
            date: date,
            stationName: station?.name,
            departures: deps,
            favouriteDepartures: WidgetFavourites.block(in: deps, favourites: favourites, at: date),
            favouriteKeys: WidgetFavourites.keys(favourites),
            asOf: Date(timeIntervalSince1970: result.fetchTime),
            isDormant: isDormant,
            currentMode: result.selectedMode,
            availableModes: result.availableModes,
            stationIndex: min(result.selectedStationIndex, max(stns.count - 1, 0)),
            stationCount: stns.count,
            hideFavouritesBlock: hideFavouritesBlock,
            outsideSwitzerland: outsideSwitzerland
        )
    }

    func favouriteRows(limit: Int) -> [WidgetDeparture] {
        guard limit > 0 else { return [] }
        return Array(favouriteDepartures.filter { !$0.isGone(at: date) }.prefix(limit))
    }

    func regularRows(limit: Int) -> [WidgetDeparture] {
        guard limit > 0 else { return [] }
        return Array(departures.filter { !$0.isGone(at: date) }.prefix(limit))
    }

    /// Favourites-first, gone-filtered list for compact surfaces (accessory + dormant rows).
    func displayDepartures(limit: Int) -> [WidgetDeparture] {
        let favs = favouriteRows(limit: limit)
        return favs + regularRows(limit: limit - favs.count)
    }

    func isFavourite(_ dep: WidgetDeparture) -> Bool { favouriteKeys.contains(dep.favKey) }

    static var placeholder: DepartureEntry {
        let now = Int(Date().timeIntervalSince1970)
        let fav = WidgetDeparture(destination: "Brig", departureTimestamp: now + 540, delay: 0, platform: "5", platformChanged: false, lineNumber: "IC8")
        let reg1 = WidgetDeparture(destination: "Zurich HB", departureTimestamp: now + 300, delay: 0, platform: "3", platformChanged: false, lineNumber: "IR16")
        let reg2 = WidgetDeparture(destination: "Basel SBB", departureTimestamp: now + 720, delay: 2, platform: "7", platformChanged: false, lineNumber: "IC6")
        return DepartureEntry(
            date: .now,
            stationName: "Bern",
            departures: [reg1, fav, reg2],
            favouriteDepartures: [fav],
            favouriteKeys: ["IC8|Brig"],
            asOf: nil,
            isDormant: false,
            currentMode: .train,
            availableModes: [.train],
            stationIndex: 0,
            stationCount: 1,
            hideFavouritesBlock: false,
            outsideSwitzerland: false
        )
    }
}
