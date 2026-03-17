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

    internal func rebuildModesAndSelect() {
        var modes: [TransportMode] = []
        if !trainStations.isEmpty { modes.append(.train) }
        if !busStations.isEmpty { modes.append(.bus) }
        if !tramStations.isEmpty { modes.append(.tram) }
        if !specialStations.isEmpty { modes.append(.special) }
        availableModes = modes

        // If current mode has no stations, prefer default mode, then first available
        if stations.isEmpty {
            if modes.contains(defaultMode) {
                currentMode = defaultMode
            } else if let firstMode = modes.first {
                currentMode = firstMode
            }
        }

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
