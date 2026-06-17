import XCTest

// Widget-extension-only storage transforms. This target compiles the widget's own sources, so the
// types are referenced directly (no import). Covers the pure selection/station rewrites; the
// SharedDefaults-backed flags (stoppedAt/hideFavouritesBlock) are app-group state, left out here.

final class WidgetStorageTests: XCTestCase {
    private func station(_ id: String, _ name: String) -> WidgetStation {
        WidgetStation(id: id, name: name, departures: [])
    }

    private func result() -> WidgetFetchResult {
        WidgetFetchResult(
            train: [station("1", "Bern"), station("2", "Thun")],
            bus: [station("3", "Köniz")], tram: [], special: [],
            selectedModeRaw: TransportMode.train.rawValue, selectedStationIndex: 0,
            fetchTime: 1_718_000_000
        )
    }

    func testUpdateSelectionChangesIndicesPreservesData() {
        let r = WidgetStorage.updateSelection(result(), modeRaw: TransportMode.bus.rawValue, stationIndex: 1)
        XCTAssertEqual(r.selectedModeRaw, TransportMode.bus.rawValue)
        XCTAssertEqual(r.selectedStationIndex, 1)
        XCTAssertEqual(r.train.map(\.name), ["Bern", "Thun"]) // data preserved
        XCTAssertEqual(r.bus.map(\.name), ["Köniz"])
        XCTAssertEqual(r.fetchTime, result().fetchTime)       // fetchTime untouched
    }

    func testUpdateStationReplacesOnlyTarget() {
        let replacement = WidgetStation(id: "9", name: "Biel", departures: [])
        let r = WidgetStorage.updateStation(result(), mode: .train, index: 0, station: replacement)
        XCTAssertEqual(r.train.map(\.name), ["Biel", "Thun"]) // index 0 replaced
        XCTAssertEqual(r.bus.map(\.name), ["Köniz"])          // other modes untouched
        XCTAssertEqual(r.selectedModeRaw, result().selectedModeRaw)
    }
}
