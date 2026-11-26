import XCTest
@testable import TrainTimePhone

// Scenario: a departure is tracked and a mode or station change reaches the
// view model without passing the locked pickers.
// Expected behaviour: the board keeps its mode and station and the session its
// departure. The same calls move the board once nothing is tracked.
final class TrackedBoardLockTests: XCTestCase {
    private var viewModel: PhoneViewModel!

    private func departure(_ destination: String) -> Departure {
        Departure(
            destination: destination, minutesUntil: 10,
            departureTimestamp: Int(Date().timeIntervalSince1970) + 600, delay: 0,
            platform: "", platformChanged: false, lineNumber: "7",
            category: "B", trainNumber: nil, operatorRef: nil
        )
    }

    // Every station carries its own board, so a change of station never fetches.
    private func station(_ id: String, _ name: String, _ mode: TransportMode, to destination: String) -> Station {
        Station(
            id: id, name: name, lat: nil, lon: nil, mode: mode, dist: nil,
            embeddedDepartures: [departure(destination)]
        )
    }

    override func setUp() {
        super.setUp()
        viewModel = PhoneViewModel()
        viewModel.trainStations = [
            station("alder", "Alder Row", .train, to: "Fenwick"),
            station("birch", "Birch Quay", .train, to: "Garsdale"),
        ]
        viewModel.busStations = [station("cedar", "Cedar Halt", .bus, to: "Holme")]
        viewModel.availableModes = [.train, .bus]
        viewModel.currentMode = .train
        viewModel.stationIndex = 0
        viewModel.departures = viewModel.trainStations[0].embeddedDepartures ?? []
    }

    override func tearDown() {
        viewModel.stopTracking()
        viewModel = nil
        super.tearDown()
    }

    private func track() {
        viewModel.selectDeparture(index: 0)
        XCTAssertEqual(viewModel.appState, 2)
        XCTAssertEqual(viewModel.focusedTrain?.destination, "Fenwick")
    }

    private func assertBoardAndSessionUnmoved(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(viewModel.currentMode, .train, file: file, line: line)
        XCTAssertEqual(viewModel.currentStation?.id, "alder", file: file, line: line)
        XCTAssertEqual(viewModel.departures.map(\.destination), ["Fenwick"], file: file, line: line)
        XCTAssertEqual(viewModel.appState, 2, file: file, line: line)
        XCTAssertEqual(viewModel.focusedTrain?.destination, "Fenwick", file: file, line: line)
    }

    func testAModeChangeWhileTrackingIsRefused() {
        track()
        viewModel.selectMode(.bus)
        assertBoardAndSessionUnmoved()
    }

    func testCyclingTheModeWhileTrackingIsRefused() {
        track()
        viewModel.cycleMode()
        assertBoardAndSessionUnmoved()
    }

    func testAStationChangeWhileTrackingIsRefused() {
        track()
        viewModel.selectStation(index: 1)
        assertBoardAndSessionUnmoved()
    }

    func testARefusedStationChangeClosesTheSheetItCameFrom() {
        track()
        viewModel.showStationPicker = true
        viewModel.selectStation(index: 1)
        XCTAssertFalse(viewModel.showStationPicker)
    }

    func testModeAndStationChangeWhenNothingIsTracked() {
        viewModel.selectStation(index: 1)
        XCTAssertEqual(viewModel.currentStation?.id, "birch")

        viewModel.selectMode(.bus)
        XCTAssertEqual(viewModel.currentMode, .bus)
        XCTAssertEqual(viewModel.currentStation?.id, "cedar")
    }

    func testStoppingTheSessionUnlocksTheBoard() {
        track()
        viewModel.stopTracking()
        XCTAssertEqual(viewModel.appState, 0)

        viewModel.selectMode(.bus)
        XCTAssertEqual(viewModel.currentMode, .bus)
        XCTAssertEqual(viewModel.currentStation?.id, "cedar")
    }
}
