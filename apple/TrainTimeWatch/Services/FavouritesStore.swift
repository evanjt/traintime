import Foundation
import WatchConnectivity

class FavouritesStore: ObservableObject {
    static let shared = FavouritesStore()

    private static let key = "favourites_v1"
    private static let maxFavourites = 20

    @Published private(set) var favourites: [Favourite] = []

    init() {
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

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(favourites) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        syncToCounterpart()
    }

    private static func load() -> [Favourite] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Favourite].self, from: data)) ?? []
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
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }
}
