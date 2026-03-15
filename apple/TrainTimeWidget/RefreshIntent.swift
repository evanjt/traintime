import AppIntents
import CoreLocation
import WidgetKit

struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Departures"
    static var description: IntentDescription = "Fetches nearby departures"

    func perform() async throws -> some IntentResult {
        // Get location
        let coordinate = try await getLocation()

        // Fetch stations + embedded departures
        let result = try await TrainAPIService.fetchStations(
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )

        // Pick the first station with departures (prefer train)
        let allStations = result.train + result.bus + result.tram + result.special
        guard let station = allStations.first(where: { $0.embeddedDepartures?.isEmpty == false }) ?? allStations.first else {
            WidgetStorage.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")
            return .result()
        }

        // Convert departures to widget format
        let deps: [WidgetDeparture]
        if let embedded = station.embeddedDepartures, !embedded.isEmpty {
            deps = embedded.map { dep in
                WidgetDeparture(
                    destination: dep.destination,
                    departureTimestamp: dep.departureTimestamp ?? 0,
                    delay: dep.delay,
                    platform: dep.platform,
                    platformChanged: dep.platformChanged,
                    lineNumber: dep.lineNumber
                )
            }
        } else {
            // Fetch departures separately if no embedded ones
            let fetched = try await TrainAPIService.fetchDepartures(stationId: station.id ?? "")
            deps = fetched.map { dep in
                WidgetDeparture(
                    destination: dep.destination,
                    departureTimestamp: dep.departureTimestamp ?? 0,
                    delay: dep.delay,
                    platform: dep.platform,
                    platformChanged: dep.platformChanged,
                    lineNumber: dep.lineNumber
                )
            }
        }

        let fetchResult = FetchResult(
            stationName: station.name ?? "Station",
            departures: deps,
            fetchTime: Date().timeIntervalSince1970
        )
        WidgetStorage.save(fetchResult)
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")

        return .result()
    }

    private func getLocation() async throws -> CLLocationCoordinate2D {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location,
               location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 1000 {
                return location.coordinate
            }
        }
        throw TrainAPIError.noData
    }
}

/// Shared storage between intent and timeline provider via UserDefaults
enum WidgetStorage {
    private static let key = "widget_fetch_result"

    static func save(_ result: FetchResult) {
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> FetchResult? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FetchResult.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
