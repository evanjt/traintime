import SwiftUI

extension TrainTimeViewModel {

    // MARK: - Mode Navigation

    func cycleMode() {
        lastInteractionTime = Date()
        guard availableModes.count > 1 else { return }
        if let idx = availableModes.firstIndex(of: currentMode) {
            let nextIdx = (idx + 1) % availableModes.count
            selectMode(availableModes[nextIdx])
        }
    }

    func selectMode(_ mode: TransportMode) {
        lastInteractionTime = Date()
        guard mode != currentMode else { return }
        currentMode = mode
        stationIndex = 0

        // Use embedded departures if available (closest station per mode)
        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            favouriteDepartures = extractFavouritesFromCurrent(deps)
            lastFetchTime = Date()
        } else {
            departures = []
            favouriteDepartures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }
    }

    // MARK: - Station Navigation

    func nextStation() {
        lastInteractionTime = Date()
        let s = stations
        guard s.count > 1 else { return }
        stationIndex = (stationIndex + 1) % s.count
        onStationSelected()
    }

    func previousStation() {
        lastInteractionTime = Date()
        let s = stations
        guard s.count > 1 else { return }
        stationIndex = stationIndex - 1
        if stationIndex < 0 { stationIndex = s.count - 1 }
        onStationSelected()
    }

    func selectStation(index: Int) {
        lastInteractionTime = Date()
        guard index >= 0, index < stations.count else { return }
        stationIndex = index
        showStationPicker = false

        // Use embedded departures if available (closest station per mode)
        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            favouriteDepartures = extractFavouritesFromCurrent(deps)
            lastFetchTime = Date()
        } else {
            departures = []
            favouriteDepartures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }
    }

    internal func onStationSelected() {
        departures = []
        favouriteDepartures = []
        if let station = currentStation, let id = station.id {
            fetchDepartures(stationId: id)
        }
    }

    // MARK: - Pinned "My stations"

    func isStationPinned(_ id: String?) -> Bool {
        guard let id else { return false }
        return MyStationsStore.shared.isPinned(id)
    }

    func togglePinnedStation(_ station: Station) {
        lastInteractionTime = Date()
        MyStationsStore.shared.toggle(station)
        // Reorder now so the picker reflects the pin without waiting for the next fetch.
        // The store's toggle() already syncs the change back to the phone over WCSession.
        applyPinnedReorder()
    }

    /// Re-sort the loaded lists so pinned stations sit at the front, keeping the
    /// currently-shown station selected (pinning sets a default, it doesn't jump).
    private func applyPinnedReorder() {
        let pinnedIds = MyStationsStore.shared.ids()
        let selectedId = currentStation?.id
        trainStations = MyStationsStore.reorder(trainStations, pinnedIds: pinnedIds)
        busStations = MyStationsStore.reorder(busStations, pinnedIds: pinnedIds)
        tramStations = MyStationsStore.reorder(tramStations, pinnedIds: pinnedIds)
        specialStations = MyStationsStore.reorder(specialStations, pinnedIds: pinnedIds)
        if let selectedId, let (mode, idx) = locate(stationId: selectedId) {
            currentMode = mode
            stationIndex = idx
        }
    }

    // MARK: - Mode Rebuilding

    /// Find a station by id across all mode arrays, returning its (mode, index).
    private func locate(stationId: String) -> (TransportMode, Int)? {
        let groups: [(TransportMode, [Station])] = [
            (.train, trainStations), (.bus, busStations),
            (.tram, tramStations), (.special, specialStations)
        ]
        for (mode, list) in groups {
            if let idx = list.firstIndex(where: { $0.id == stationId }) {
                return (mode, idx)
            }
        }
        return nil
    }

    /// Rebuild the mode list after a station fetch. When `preserveStationId` still
    /// exists in the new results, keep the user on that station/mode (in-place refresh,
    /// no reset to the nearest station); otherwise fall back to selecting the nearest.
    internal func rebuildModesAndSelect(preserveStationId: String? = nil) {
        var modes: [TransportMode] = []
        if !trainStations.isEmpty { modes.append(.train) }
        if !busStations.isEmpty { modes.append(.bus) }
        if !tramStations.isEmpty { modes.append(.tram) }
        if !specialStations.isEmpty { modes.append(.special) }
        availableModes = modes

        var preserved = false
        if let id = preserveStationId, let (mode, idx) = locate(stationId: id) {
            currentMode = mode
            stationIndex = idx
            preserved = true
        } else {
            // If current mode has no stations, prefer default mode, then first available
            if stations.isEmpty {
                if modes.contains(defaultMode) {
                    currentMode = defaultMode
                } else if let firstMode = modes.first {
                    currentMode = firstMode
                }
            }
            stationIndex = 0
        }

        // Adopt fresh embedded departures if present. On the non-preserved path, blank
        // and refetch. On the preserved path with no fresh embedded departures, leave the
        // existing list untouched (no flash), the timer refresh updates it in place.
        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            favouriteDepartures = extractFavouritesFromCurrent(deps)
            lastFetchTime = Date()
        } else if !preserved {
            departures = []
            favouriteDepartures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }
    }

    // MARK: - State Reset

    internal func clearStationState() {
        trainStations = []
        busStations = []
        tramStations = []
        specialStations = []
        stationIndex = 0
        departures = []
        favouriteDepartures = []
        availableModes = []
        consecutiveErrors = 0

        if appState == 2 {
            exitToStationView()
        }

        routing.clearCache()
        status = "Finding stations..."
    }

    // MARK: - Helpers

    private func extractFavouritesFromCurrent(_ deps: [Departure]) -> [Departure] {
        guard let stationId = currentStation?.id else { return [] }
        return favouritesStore.extractFavourites(from: deps, stationId: stationId)
    }
}
