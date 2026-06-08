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
            lastFetchTime = Date()
        } else {
            departures = []
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
            lastFetchTime = Date()
        } else {
            departures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }
    }

    internal func onStationSelected() {
        departures = []
        if let station = currentStation, let id = station.id {
            fetchDepartures(stationId: id)
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
        // existing list untouched (no flash) — the timer refresh updates it in place.
        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            lastFetchTime = Date()
        } else if !preserved {
            departures = []
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
        availableModes = []
        consecutiveErrors = 0

        if appState == 2 {
            exitToStationView()
        }

        routing.clearCache()
        status = "Finding stations..."
    }
}
