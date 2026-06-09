import AppIntents
import WidgetKit

struct SwitchStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Station"
    static var description: IntentDescription = "Cycles to next station within current mode"

    func perform() async throws -> some IntentResult {
        guard var result = WidgetStorage.load() else { return .result() }

        let mode = result.selectedMode
        let stations = result.stations(for: mode)
        guard stations.count > 1 else { return .result() }

        let nextIdx = (result.selectedStationIndex + 1) % stations.count
        result = WidgetStorage.updateSelection(result, modeRaw: result.selectedModeRaw, stationIndex: nextIdx)

        // Fetch departures for the new station if it has none
        if stations[nextIdx].departures.isEmpty {
            let favParam = FavouritesStore.shared.favouritesParam(forStation: stations[nextIdx].id)
            if let fetched = try? await TrainAPIService.fetchDepartures(stationId: stations[nextIdx].id, favourites: favParam) {
                let favDeps = !fetched.favourites.isEmpty
                    ? fetched.favourites
                    : FavouritesStore.shared.extractFavourites(from: fetched.departures, stationId: stations[nextIdx].id)
                let deps = (favDeps + fetched.departures).map { dep in
                    WidgetDeparture(
                        destination: dep.destination,
                        departureTimestamp: dep.departureTimestamp ?? 0,
                        delay: dep.delay,
                        platform: dep.platform,
                        platformChanged: dep.platformChanged,
                        lineNumber: dep.lineNumber
                    )
                }
                let updated = WidgetStation(id: stations[nextIdx].id, name: stations[nextIdx].name, departures: deps)
                result = WidgetStorage.updateStation(result, mode: mode, index: nextIdx, station: updated)
            }
        }

        WidgetStorage.save(result)
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")

        return .result()
    }
}
