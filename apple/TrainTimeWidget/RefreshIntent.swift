import AppIntents
import CoreLocation
import WidgetKit

struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Departures"
    static var description: IntentDescription = "Fetches nearby departures"

    func perform() async throws -> some IntentResult {
        FavouritesStore.shared.reload() // pick up app-side favourite changes in this process
        let coordinate = try await getLocation()

        let result = try await TrainAPIService.fetchStations(
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )

        let previous = WidgetStorage.load()

        var trainStations = convertStations(result.train)
        var busStations = convertStations(result.bus)
        var tramStations = convertStations(result.tram)
        var specialStations = convertStations(result.special)

        // Determine mode/station selection, preserving previous if still valid
        var modeRaw = previous?.selectedModeRaw ?? TransportMode.train.rawValue
        var stationIdx = previous?.selectedStationIndex ?? 0

        // Validate selection
        let tempResult = WidgetFetchResult(
            train: trainStations, bus: busStations, tram: tramStations, special: specialStations,
            selectedModeRaw: modeRaw, selectedStationIndex: stationIdx,
            fetchTime: Date().timeIntervalSince1970
        )
        let mode = tempResult.selectedMode
        if tempResult.stations(for: mode).isEmpty {
            if let first = tempResult.availableModes.first {
                modeRaw = first.rawValue
            }
            stationIdx = 0
        } else {
            let stns = tempResult.stations(for: mode)
            if stationIdx >= stns.count {
                stationIdx = 0
            }
        }

        // Fetch departures for the selected station if it has none embedded
        let selectedMode = TransportMode(rawValue: modeRaw) ?? .train
        let selectedStations: [WidgetStation]
        switch selectedMode {
        case .train: selectedStations = trainStations
        case .bus: selectedStations = busStations
        case .tram: selectedStations = tramStations
        case .special: selectedStations = specialStations
        }
        if stationIdx < selectedStations.count && selectedStations[stationIdx].departures.isEmpty {
            let station = selectedStations[stationIdx]
            let favParam = FavouritesStore.shared.favouritesParam(forStation: station.id)
            if let result = try? await TrainAPIService.fetchDepartures(stationId: station.id, favourites: favParam) {
                // Store one clean, time-ordered list. Favourites are flagged later at
                // timeline-build time; merging only re-inserts any server favourite that
                // departs beyond the regular list horizon.
                let allDeps = FavouritesStore.shared.merging(favourites: result.favourites, into: result.departures)
                let deps = allDeps.map { dep in
                    WidgetDeparture(
                        destination: dep.destination,
                        departureTimestamp: dep.departureTimestamp ?? 0,
                        delay: dep.delay,
                        platform: dep.platform,
                        platformChanged: dep.platformChanged,
                        lineNumber: dep.lineNumber
                    )
                }
                let updated = WidgetStation(id: station.id, name: station.name, departures: deps)
                switch selectedMode {
                case .train: trainStations[stationIdx] = updated
                case .bus: busStations[stationIdx] = updated
                case .tram: tramStations[stationIdx] = updated
                case .special: specialStations[stationIdx] = updated
                }
            }
        }

        let finalResult = WidgetFetchResult(
            train: trainStations, bus: busStations, tram: tramStations, special: specialStations,
            selectedModeRaw: modeRaw, selectedStationIndex: stationIdx,
            fetchTime: Date().timeIntervalSince1970
        )

        WidgetStorage.save(finalResult)
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")

        return .result()
    }

    private func convertStations(_ stations: [Station]) -> [WidgetStation] {
        stations.compactMap { station in
            guard let id = station.id, let name = station.name else { return nil }
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
                deps = []
            }
            return WidgetStation(id: id, name: name, departures: deps)
        }
    }

    private func getLocation() async throws -> CLLocationCoordinate2D {
        try await withThrowingTaskGroup(of: CLLocationCoordinate2D.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location,
                       location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 1000 {
                        return location.coordinate
                    }
                }
                throw TrainAPIError.noData
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw TrainAPIError.noData
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

/// Shared storage between intent and timeline provider via the App Group container.
enum WidgetStorage {
    // v3: favourites are no longer pre-prepended into the stored list (the provider derives
    // them per entry), so the old v2 cache has incompatible semantics and is abandoned.
    private static let key = "widget_fetch_result_v3"

    static func save(_ result: WidgetFetchResult) {
        if let data = try? JSONEncoder().encode(result) {
            SharedDefaults.store.set(data, forKey: key)
        }
    }

    static func load() -> WidgetFetchResult? {
        guard let data = SharedDefaults.store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetFetchResult.self, from: data)
    }

    static func clear() {
        SharedDefaults.store.removeObject(forKey: key)
    }

    static func updateSelection(_ result: WidgetFetchResult, modeRaw: Int, stationIndex: Int) -> WidgetFetchResult {
        WidgetFetchResult(
            train: result.train, bus: result.bus, tram: result.tram, special: result.special,
            selectedModeRaw: modeRaw, selectedStationIndex: stationIndex,
            fetchTime: result.fetchTime
        )
    }

    /// Replace a single station's data within the stored result
    static func updateStation(_ result: WidgetFetchResult, mode: TransportMode, index: Int, station: WidgetStation) -> WidgetFetchResult {
        var train = result.train, bus = result.bus, tram = result.tram, special = result.special
        switch mode {
        case .train: train[index] = station
        case .bus: bus[index] = station
        case .tram: tram[index] = station
        case .special: special[index] = station
        }
        return WidgetFetchResult(
            train: train, bus: bus, tram: tram, special: special,
            selectedModeRaw: result.selectedModeRaw, selectedStationIndex: result.selectedStationIndex,
            fetchTime: result.fetchTime
        )
    }
}
