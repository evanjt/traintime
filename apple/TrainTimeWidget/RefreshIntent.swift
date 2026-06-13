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
    // The cache key + codec live on WidgetFetchResult (shared with the phone target), so the
    // app can seed the same cache the widget reads. v3: favourites are no longer pre-prepended
    // into the stored list (the provider derives them per entry).
    static func save(_ result: WidgetFetchResult) { result.cache() }

    static func load() -> WidgetFetchResult? { WidgetFetchResult.loadCached() }

    static func clear() {
        SharedDefaults.store.removeObject(forKey: WidgetFetchResult.cacheKey)
    }

    // Display preference (not fetched data): when true the widget hides the favourites block
    // and shows departures in pure time order, with favourites still starred inline.
    private static let hideFavKey = "widget_hide_favourites_block"

    static var hideFavouritesBlock: Bool {
        get { SharedDefaults.store.bool(forKey: hideFavKey) }
        set { SharedDefaults.store.set(newValue, forKey: hideFavKey) }
    }

    // Manual stop: when the user taps Stop, we stamp the time. The provider treats a stop newer
    // than the last fetchTime as dormant, so the breaker opens immediately. A Refresh (or the app
    // seeding a fresh fetchTime) supersedes it and re-activates the live window.
    private static let stoppedAtKey = "widget_stopped_at"

    static var stoppedAt: TimeInterval {
        get { SharedDefaults.store.double(forKey: stoppedAtKey) }
        set { SharedDefaults.store.set(newValue, forKey: stoppedAtKey) }
    }

    static func stop() { stoppedAt = Date().timeIntervalSince1970 }

    static func isStopped(since fetchTime: TimeInterval) -> Bool { stoppedAt > fetchTime }

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

/// Toggles the favourites-grouping display mode. No network — flips a flag and reloads.
struct ToggleFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Favourites Grouping"
    static var description: IntentDescription = "Show favourites first, or all departures in time order"

    func perform() async throws -> some IntentResult {
        WidgetStorage.hideFavouritesBlock.toggle()
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")
        return .result()
    }
}

/// Drops the widget back to its dormant state at once, without waiting out the active window.
/// No network — stamps the stop time and reloads. The next Refresh re-activates it.
struct StopIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Live Updates"
    static var description: IntentDescription = "Return the widget to its dormant state"

    func perform() async throws -> some IntentResult {
        WidgetStorage.stop()
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")
        return .result()
    }
}
