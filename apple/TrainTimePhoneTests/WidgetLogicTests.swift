import XCTest
@testable import TrainTimePhone

// Widget logic compiled into the phone target (WidgetEntry.swift). Mirrors Android's WidgetLogicTest.
// Every time-dependent path takes an injected `now`, never Date(), so results are deterministic.

final class WidgetLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_718_000_000)
    private var nowTs: Int { Int(now.timeIntervalSince1970) }

    private func dep(_ line: String, _ dest: String, in offset: Int, delay: Int = 0) -> WidgetDeparture {
        WidgetDeparture(
            destination: dest, departureTimestamp: nowTs + offset, delay: delay,
            platform: "3", platformChanged: false, lineNumber: line
        )
    }

    private func station(_ id: String, _ name: String, _ deps: [WidgetDeparture] = []) -> WidgetStation {
        WidgetStation(id: id, name: name, departures: deps)
    }

    private func fav(_ line: String, _ dest: String) -> Favourite {
        Favourite(stationId: "8501120", stationName: "Lausanne", lineNumber: line, destination: dest)
    }

    private func result(
        train: [WidgetStation] = [], bus: [WidgetStation] = [],
        tram: [WidgetStation] = [], special: [WidgetStation] = [],
        mode: TransportMode = .train, stationIndex: Int = 0
    ) -> WidgetFetchResult {
        WidgetFetchResult(
            train: train, bus: bus, tram: tram, special: special,
            selectedModeRaw: mode.rawValue, selectedStationIndex: stationIndex,
            fetchTime: now.timeIntervalSince1970
        )
    }

    func testMinutesTextCoversGoneNowAndMinutes() {
        XCTAssertEqual(dep("IC8", "Brig", in: -90).minutesText(at: now), "gone")
        XCTAssertEqual(dep("IC8", "Brig", in: 30).minutesText(at: now), "now")
        XCTAssertEqual(dep("IC8", "Brig", in: 600).minutesText(at: now), "10'")
    }

    func testIsGoneOncePastByAFullMinute() {
        // isGone is minute-granular (integer division): a sub-minute-old departure still reads "now".
        XCTAssertFalse(dep("IC8", "Brig", in: -30).isGone(at: now))
        XCTAssertTrue(dep("IC8", "Brig", in: -90).isGone(at: now))
        XCTAssertFalse(dep("IC8", "Brig", in: 60).isGone(at: now))
    }

    func testFavouritesBlockTakesOneNotGonePerKeyTimeOrdered() {
        let deps = [
            dep("IR90", "Genève", in: 300),
            dep("IC8", "Brig", in: -60),   // gone, skipped
            dep("IC8", "Brig", in: 120),   // first live IC8 → kept
            dep("IC8", "Brig", in: 600),   // duplicate key, skipped
        ]
        let block = WidgetFavourites.block(in: deps, favourites: [fav("IC8", "Brig"), fav("IR90", "Genève")], at: now)
        XCTAssertEqual(block.map(\.lineNumber), ["IC8", "IR90"]) // 120s sorts before 300s
    }

    func testFavouritesBlockEmptyWithoutFavourites() {
        XCTAssertTrue(WidgetFavourites.block(in: [dep("IC8", "Brig", in: 120)], favourites: [], at: now).isEmpty)
    }

    func testAvailableModesListsOnlyNonEmptyGroups() {
        let s = station("1", "A", [dep("IC8", "Brig", in: 120)])
        XCTAssertEqual(result(train: [s], tram: [s]).availableModes, [.train, .tram])
    }

    func testCurrentStationClampsOutOfRangeIndex() {
        let r = result(train: [station("1", "A"), station("2", "B")], stationIndex: 5)
        XCTAssertEqual(r.currentStation?.name, "B")
    }

    func testCurrentStationNilWhenSelectedModeEmpty() {
        // Selected mode is train but only the bus group has stations.
        XCTAssertNil(result(bus: [station("1", "A")], mode: .train).currentStation)
    }
}
