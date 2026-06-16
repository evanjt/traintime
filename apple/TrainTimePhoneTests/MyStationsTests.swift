import XCTest
@testable import TrainTimePhone

// Mirrors the Android MyStationsLogicTest: the pinned-station reorder precedence
// and PinnedStation persistence. linePill colour mapping isn't asserted here
// because AppColors' adaptive colours are dynamic (not value-equatable).
final class MyStationsTests: XCTestCase {
    private func station(_ id: String) -> Station {
        Station(id: id, name: id, lat: nil, lon: nil, mode: .train, dist: nil, embeddedDepartures: nil)
    }

    private var nearby: [Station] { [station("near"), station("big"), station("far")] }

    func testReorderNoPinsKeepsDistanceOrder() {
        XCTAssertEqual(MyStationsStore.reorder(nearby, pinnedIds: []).compactMap { $0.id }, ["near", "big", "far"])
    }

    func testReorderBubblesPinnedToFront() {
        XCTAssertEqual(MyStationsStore.reorder(nearby, pinnedIds: ["big"]).compactMap { $0.id }, ["big", "near", "far"])
    }

    func testReorderIgnoresAbsentPin() {
        XCTAssertEqual(MyStationsStore.reorder(nearby, pinnedIds: ["zurich"]).compactMap { $0.id }, ["near", "big", "far"])
    }

    func testReorderPreservesGroupOrder() {
        XCTAssertEqual(
            MyStationsStore.reorder(nearby, pinnedIds: ["near", "far"]).compactMap { $0.id },
            ["near", "far", "big"],
        )
    }

    func testPinnedStationCodableRoundTrip() throws {
        let pin = PinnedStation(id: "8500074", name: "Sion", lat: 46.23, lon: 7.36)
        let data = try JSONEncoder().encode([pin])
        let decoded = try JSONDecoder().decode([PinnedStation].self, from: data)
        XCTAssertEqual(decoded, [pin])
    }
}
