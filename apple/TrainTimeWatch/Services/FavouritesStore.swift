import Foundation
import WatchConnectivity
#if os(iOS)
import WidgetKit
#endif

class FavouritesStore: ObservableObject {
    static let shared = FavouritesStore()

    private static let key = "favourites_v1"
    private static let maxFavourites = 20

    @Published private(set) var favourites: [Favourite] = []

    init() {
        favourites = Self.load()
    }

    /// Re-read from storage. The widget extension process is long-lived and this singleton
    /// only loads once, so the timeline provider/intents call this to see app-side toggles.
    func reload() {
        favourites = Self.load()
    }

    // MARK: - CRUD

    func add(_ favourite: Favourite) {
        guard !favourites.contains(favourite) else { return }
        guard favourites.count < Self.maxFavourites else { return }
        favourites.append(favourite)
        save()
    }

    func remove(_ favourite: Favourite) {
        favourites.removeAll { $0 == favourite }
        save()
    }

    func removeAll() {
        favourites.removeAll()
        save()
    }

    func isFavourite(stationId: String, lineNumber: String, destination: String) -> Bool {
        favourites.contains { $0.stationId == stationId && $0.lineNumber == lineNumber && $0.destination == destination }
    }

    func toggle(stationId: String, stationName: String, lineNumber: String, destination: String) {
        if isFavourite(stationId: stationId, lineNumber: lineNumber, destination: destination) {
            favourites.removeAll { $0.stationId == stationId && $0.lineNumber == lineNumber && $0.destination == destination }
        } else if favourites.count < Self.maxFavourites {
            favourites.append(Favourite(stationId: stationId, stationName: stationName, lineNumber: lineNumber, destination: destination))
        }
        save()
    }

    /// Favourites for a specific station
    func favouritesForStation(_ stationId: String) -> [Favourite] {
        favourites.filter { $0.stationId == stationId }
    }

    /// Extract favourite departures from a departure list for a given station.
    /// Returns first match per favourite, sorted by departure time.
    func extractFavourites(from departures: [Departure], stationId: String) -> [Departure] {
        let stationFavs = favouritesForStation(stationId)
        guard !stationFavs.isEmpty else { return [] }

        var result: [Departure] = []
        for fav in stationFavs {
            if let match = departures.first(where: { $0.lineNumber == fav.lineNumber && $0.destination == fav.destination }) {
                result.append(match)
            }
        }
        return result.sorted { ($0.departureTimestamp ?? 0) < ($1.departureTimestamp ?? 0) }
    }

    /// Build URL query param for server-side filtering: "IC8:Brig,IR90:Visp"
    func favouritesParam(forStation stationId: String) -> String? {
        let stationFavs = favouritesForStation(stationId)
        guard !stationFavs.isEmpty else { return nil }
        return stationFavs.map { "\($0.lineNumber):\($0.destination)" }.joined(separator: ",")
    }

    /// Keep favourite departures present in the regular list so they repeat in time order.
    /// Client-side extraction already pulls favourites from `departures`; this covers a
    /// server that returns favourites as a separate array without keeping them in `departures`.
    func merging(favourites: [Departure], into departures: [Departure]) -> [Departure] {
        guard !favourites.isEmpty else { return departures }
        var result = departures
        for fav in favourites {
            let present = departures.contains {
                $0.lineNumber == fav.lineNumber
                    && $0.destination == fav.destination
                    && $0.departureTimestamp == fav.departureTimestamp
            }
            if !present { result.append(fav) }
        }
        return result.sorted { ($0.departureTimestamp ?? 0) < ($1.departureTimestamp ?? 0) }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(favourites) {
            SharedDefaults.store.set(data, forKey: Self.key)
        }
        syncToCounterpart()
        reloadWidget()
    }

    private static func load() -> [Favourite] {
        let store = SharedDefaults.store
        #if os(iOS)
        // One-time migration from the app's standard defaults into the App Group container
        // (favourites predate the shared suite). No-op in the widget process (empty .standard).
        if store.data(forKey: key) == nil,
           let legacy = UserDefaults.standard.data(forKey: key) {
            store.set(legacy, forKey: key)
        }
        #endif
        guard let data = store.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Favourite].self, from: data)) ?? []
    }

    /// Favourites changing in the app must invalidate the widget timeline so stars/blocks
    /// re-render. The provider re-derives them from storage, so no network is involved.
    private func reloadWidget() {
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")
        #endif
    }

    // MARK: - WCSession Sync

    func syncToCounterpart() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if let data = try? JSONEncoder().encode(favourites) {
            var context = WCSession.default.applicationContext
            context["favourites"] = data
            try? WCSession.default.updateApplicationContext(context)
        }
    }

    func handleReceivedContext(_ context: [String: Any]) {
        guard let data = context["favourites"] as? Data,
              let decoded = try? JSONDecoder().decode([Favourite].self, from: data) else { return }
        favourites = decoded
        if let encoded = try? JSONEncoder().encode(favourites) {
            SharedDefaults.store.set(encoded, forKey: Self.key)
        }
        reloadWidget()
    }
}

/// Unified "My stations" (pinned). Mirrors FavouritesStore's storage + WCSession
/// sync path. A pinned station bubbles to the front of the nearby list and becomes
/// the default shown station. Lives in this file to ride its all-targets membership.
class MyStationsStore: ObservableObject {
    static let shared = MyStationsStore()

    private static let key = "myStations_v1"
    private static let maxPinned = 10

    @Published private(set) var pinned: [PinnedStation] = []

    init() {
        pinned = Self.load()
    }

    func reload() {
        pinned = Self.load()
    }

    func ids() -> Set<String> { Set(pinned.map { $0.id }) }

    func isPinned(_ id: String) -> Bool { pinned.contains { $0.id == id } }

    func toggle(_ station: Station) {
        guard let id = station.id, let name = station.name else { return }
        if pinned.contains(where: { $0.id == id }) {
            pinned.removeAll { $0.id == id }
        } else if pinned.count < Self.maxPinned {
            pinned.append(PinnedStation(id: id, name: name, lat: station.lat, lon: station.lon))
        }
        save()
    }

    func remove(_ id: String) {
        pinned.removeAll { $0.id == id }
        save()
    }

    /// Bubble pinned ids to the front, preserving the API's distance order. Shared
    /// by the app view models and the widget refresh intent.
    static func reorder(_ stations: [Station], pinnedIds: Set<String>) -> [Station] {
        guard !pinnedIds.isEmpty else { return stations }
        let isPinned: (Station) -> Bool = { $0.id.map(pinnedIds.contains) ?? false }
        return stations.filter(isPinned) + stations.filter { !isPinned($0) }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(pinned) {
            SharedDefaults.store.set(data, forKey: Self.key)
        }
        syncToCounterpart()
        reloadWidget()
    }

    private static func load() -> [PinnedStation] {
        guard let data = SharedDefaults.store.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PinnedStation].self, from: data)) ?? []
    }

    private func reloadWidget() {
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")
        #endif
    }

    // MARK: - WCSession Sync

    func syncToCounterpart() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if let data = try? JSONEncoder().encode(pinned) {
            var context = WCSession.default.applicationContext
            context["myStations"] = data
            try? WCSession.default.updateApplicationContext(context)
        }
    }

    func handleReceivedContext(_ context: [String: Any]) {
        guard let data = context["myStations"] as? Data,
              let decoded = try? JSONDecoder().decode([PinnedStation].self, from: data) else { return }
        pinned = decoded
        if let encoded = try? JSONEncoder().encode(pinned) {
            SharedDefaults.store.set(encoded, forKey: Self.key)
        }
        reloadWidget()
    }
}
