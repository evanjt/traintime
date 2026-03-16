import AppIntents
import WidgetKit

struct SwitchModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Mode"
    static var description: IntentDescription = "Cycles to next transport mode"

    func perform() async throws -> some IntentResult {
        guard var result = WidgetStorage.load() else { return .result() }

        let modes = result.availableModes
        guard modes.count > 1 else { return .result() }

        let currentIdx = modes.firstIndex(of: result.selectedMode) ?? 0
        let nextIdx = (currentIdx + 1) % modes.count
        let nextMode = modes[nextIdx]

        result = WidgetStorage.updateSelection(result, modeRaw: nextMode.rawValue, stationIndex: 0)

        // Fetch departures for the new station if it has none
        let stations = result.stations(for: nextMode)
        if !stations.isEmpty && stations[0].departures.isEmpty {
            if let fetched = try? await TrainAPIService.fetchDepartures(stationId: stations[0].id) {
                let deps = fetched.map { dep in
                    WidgetDeparture(
                        destination: dep.destination,
                        departureTimestamp: dep.departureTimestamp ?? 0,
                        delay: dep.delay,
                        platform: dep.platform,
                        platformChanged: dep.platformChanged,
                        lineNumber: dep.lineNumber
                    )
                }
                let updated = WidgetStation(id: stations[0].id, name: stations[0].name, departures: deps)
                result = WidgetStorage.updateStation(result, mode: nextMode, index: 0, station: updated)
            }
        }

        WidgetStorage.save(result)
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")

        return .result()
    }
}
