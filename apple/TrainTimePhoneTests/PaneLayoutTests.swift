import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import TrainTimePhone

final class PaneLayoutTests: XCTestCase {
    func testRegularTrackingSplitsBoardAndTracking() {
        XCTAssertEqual(paneLayout(.regular, appState: 2), .splitTracking)
    }

    func testRegularIdleSplitsBoardAndHint() {
        XCTAssertEqual(paneLayout(.regular, appState: 0), .splitHint)
        XCTAssertEqual(paneLayout(.regular, appState: 3), .splitHint)
    }

    func testCompactKeepsTheSingleScreenFlow() {
        for sizeClass in [UserInterfaceSizeClass.compact, nil] {
            XCTAssertEqual(paneLayout(sizeClass, appState: 2), .tracking)
            XCTAssertEqual(paneLayout(sizeClass, appState: 0), .board)
            XCTAssertEqual(paneLayout(sizeClass, appState: 3), .board)
        }
    }

    func testBoardKeepsAReadableWidthAndLeavesTrackingRoom() {
        XCTAssertEqual(boardPaneWidth(totalWidth: 600), 300)
        XCTAssertEqual(boardPaneWidth(totalWidth: 669), 309)
        XCTAssertEqual(boardPaneWidth(totalWidth: 720), 360)
        XCTAssertEqual(boardPaneWidth(totalWidth: 1100), 400)
    }

    func testOnlyTrackingLocksTheBoardPickers() {
        XCTAssertTrue(boardPickersLocked(appState: 2))
        XCTAssertFalse(boardPickersLocked(appState: 0))
        XCTAssertFalse(boardPickersLocked(appState: 3))
    }

    private func row(_ dest: String, _ ts: Int, train: String?) -> Departure {
        Departure(
            destination: dest, minutesUntil: 6, departureTimestamp: ts, delay: 0,
            platform: "3", platformChanged: false, lineNumber: "IR15",
            category: "IR", trainNumber: train, operatorRef: nil
        )
    }

    private func focused(_ dest: String, train: String?) -> FocusedDeparture {
        FocusedDeparture(
            destination: dest, departureTimestamp: 1_718_000_360, lineNumber: "IR15",
            category: "IR", trainNumber: train, operatorRef: nil, delay: 0,
            platform: "3", platformChanged: false)
    }

    func testRetappingTheTrackedDepartureKeepsTheSession() {
        let tracked = focused("Luzern", train: nil)
        XCTAssertTrue(isAlreadyTracked(row("Luzern", 1_718_000_360, train: nil), appState: 2, focused: tracked))
        XCTAssertFalse(isAlreadyTracked(row("Basel SBB", 1_718_000_360, train: nil), appState: 2, focused: tracked))
        XCTAssertFalse(isAlreadyTracked(row("Luzern", 1_718_000_360, train: nil), appState: 0, focused: tracked))
    }

    func testTheTrackedRowIsMarkedWhileTracking() {
        let rows = [
            row("Basel SBB", 1_718_000_360, train: "2511"),
            row("Luzern", 1_718_000_360, train: "2515"),
            row("Luzern", 1_718_000_960, train: "2517"),
        ]
        XCTAssertEqual(trackedRowIndex(rows, appState: 2, focused: focused("Luzern", train: "2515")), 1)
    }

    // Two journeys on the same line at the same minute to the same place differ
    // only by train number, so only the tracked one is marked.
    func testATwinOfAnotherJourneyIsNotMarked() {
        let rows = [row("Luzern", 1_718_000_360, train: "92515"), row("Luzern", 1_718_000_360, train: "2515")]
        let tracked = focused("Luzern", train: "2515")
        XCTAssertEqual(trackedRowIndex(rows, appState: 2, focused: tracked), 1)
        XCTAssertFalse(isAlreadyTracked(rows[0], appState: 2, focused: tracked))
        XCTAssertTrue(isAlreadyTracked(rows[1], appState: 2, focused: tracked))
    }

    func testWithoutATrainNumberTheDestinationIdentifiesTheRow() {
        let rows = [row("Basel SBB", 1_718_000_360, train: nil), row("Luzern", 1_718_000_360, train: nil)]
        XCTAssertEqual(trackedRowIndex(rows, appState: 2, focused: focused("Luzern", train: nil)), 1)
    }

    func testNothingIsMarkedWithoutASessionOrAMatch() {
        let rows = [row("Luzern", 1_718_000_360, train: "2515")]
        let tracked = focused("Luzern", train: "2515")
        XCTAssertNil(trackedRowIndex(rows, appState: 0, focused: tracked))
        XCTAssertNil(trackedRowIndex(rows, appState: 3, focused: tracked))
        XCTAssertNil(trackedRowIndex(rows, appState: 2, focused: nil))
        XCTAssertNil(trackedRowIndex([row("Luzern", 1_718_000_960, train: "2517")], appState: 2, focused: tracked))
    }

    // The split at the iPhone Duo inner display (2007x2853 px at 3x).
    private let duoInner = CGSize(width: 669, height: 951)
    private let nowTs = 1_718_000_000

    private func dep(_ line: String, _ dest: String, min: Int, delay: Int = 0) -> Departure {
        Departure(
            destination: dest, minutesUntil: min,
            departureTimestamp: nowTs + min * 60, delay: delay,
            platform: "3", platformChanged: false, lineNumber: line,
            category: "IC", trainNumber: nil, operatorRef: nil
        )
    }

    private var rows: [Departure] {
        [dep("IR15", "Luzern", min: 6), dep("IC8", "Romanshorn", min: 8, delay: 1),
         dep("S7", "Worb Dorf", min: 11), dep("RE90", "Biel/Bienne", min: 14)]
    }

    // The tracking pane shows the IR15, so its row is the one marked.
    private let trackedIr15 = 0

    private func board(tracked: Int?) -> some View {
        VStack(spacing: 0) {
            Text("Bern")
                .font(.title.weight(.bold))
                .padding(.vertical, 10)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let selected = index == tracked
                PhoneDepartureRowView(departure: row, mode: .train, isSelected: selected)
                    .padding(.horizontal, 12)
                    .background(boardRowFill(isSelected: selected, isFavourite: false))
            }
            Spacer()
        }
    }

    private var tracking: some View {
        VStack(spacing: 16) {
            Text("Luzern").font(.title2.weight(.bold))
            Text("6 min").font(.system(size: 64, weight: .bold, design: .rounded))
            TrackingBarView(schedBuf: 4, effectBuf: 5, hasGPS: true)
            Spacer()
        }
        .padding(16)
    }

    private func assertSplit(_ detail: some View, _ name: String, styles: [(String, UIUserInterfaceStyle)],
                             tracked: Int?, testName: String = #function, line: UInt = #line) {
        let view = TwoPaneLayout(board: { self.board(tracked: tracked) }, detail: { detail })
            .frame(width: duoInner.width, height: duoInner.height)
            .background(Color(uiColor: .systemBackground))
        for (suffix, style) in styles {
            assertSnapshot(
                of: view,
                as: .image(precision: 0.99, perceptualPrecision: 0.98,
                           layout: .fixed(width: duoInner.width, height: duoInner.height),
                           traits: .init(userInterfaceStyle: style)),
                named: "\(name)_\(suffix)", testName: testName, line: line
            )
        }
    }

    func testSplitTrackingAtDuoInnerSize() {
        assertSplit(tracking, "split_tracking", styles: [("light", .light), ("dark", .dark)], tracked: trackedIr15)
    }

    func testSplitHintAtDuoInnerSize() {
        assertSplit(TrackingPaneHint(), "split_hint", styles: [("light", .light)], tracked: nil)
    }
}
