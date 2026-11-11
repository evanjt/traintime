import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import TrainTimePhone

final class PaneLayoutTests: XCTestCase {
    func testACompactPhoneShowsTheBoardThenTrackingFullScreen() {
        XCTAssertEqual(paneLayout(width: 393, height: 852, appState: 0).mode, .board)
        XCTAssertEqual(paneLayout(width: 393, height: 852, appState: 3).mode, .board)
        XCTAssertEqual(paneLayout(width: 393, height: 852, appState: 2).mode, .tracking)
    }

    func testACompactHeightWindowNeverSplitsOrShowsTheCard() {
        for (w, h) in [(678.0, 466.0), (956.0, 440.0)] {
            XCTAssertEqual(paneLayout(width: w, height: h, appState: 0).mode, .board)
            XCTAssertEqual(paneLayout(width: w, height: h, appState: 2).mode, .tracking)
        }
    }

    func testTwoPhoneWidthPanesSitSideBySideSplitAtTheMiddle() {
        for appState in [0, 2] {
            let duo = paneLayout(width: 951, height: 669, appState: appState)
            XCTAssertEqual(duo.mode, .sideBySide)
            XCTAssertEqual(duo.boardWidth, 475)
            XCTAssertEqual(951 - duo.detailStart, 475)
        }
        let tablet = paneLayout(width: 1280, height: 800, appState: 2)
        XCTAssertEqual(tablet.mode, .sideBySide)
        XCTAssertGreaterThanOrEqual(tablet.boardWidth, boardNormalWidth)
        XCTAssertGreaterThanOrEqual(1280 - tablet.detailStart, boardNormalWidth)
    }

    func testANarrowerWideWindowRestsTheCardAtPeekWhileIdle() {
        for (w, h) in [(669.0, 951.0), (674.0, 841.0)] {
            for appState in [0, 3] {
                let peek = paneLayout(width: w, height: h, appState: appState, stop: .half)
                XCTAssertEqual(peek.mode, .card)
                XCTAssertEqual(peek.stop, .peek)
                XCTAssertGreaterThanOrEqual(peek.boardWidth, boardNormalWidth)
                XCTAssertLessThanOrEqual(peek.boardWidth, 466)
                XCTAssertGreaterThanOrEqual(w - peek.detailStart, 200)
            }
        }
    }

    func testTheDuoTurnedKeepsTheBoardReadableAtPeek() {
        XCTAssertEqual(paneLayout(width: 669, height: 951, appState: 0).boardWidth, 466)
    }

    func testStartingTrackingOpensTheCardAtHalf() {
        for (w, h) in [(669.0, 951.0), (674.0, 841.0)] {
            let half = paneLayout(width: w, height: h, appState: 2)
            XCTAssertEqual(half.mode, .card)
            XCTAssertEqual(half.stop, .half)
            XCTAssertGreaterThanOrEqual(w - half.detailStart, 360)
            XCTAssertEqual(half.boardWidth, half.detailStart)
        }
    }

    func testTheCardTakesTheWholeWindowAtFull() {
        XCTAssertEqual(
            paneLayout(width: 674, height: 841, appState: 2, stop: .full),
            PaneLayout(mode: .card, stop: .full, boardWidth: 0, detailStart: 0))
    }

    private let duoTurned = CGSize(width: 669, height: 951)
    private let duoOpen = CGSize(width: 951, height: 669)

    private func stop(_ choice: CardStopChoice, _ size: CGSize, appState: Int) -> CardStop? {
        choice.layout(width: size.width, height: size.height, appState: appState).stop
    }

    func testTrackingOpensTheCardAtHalfAndStoppingReturnsItToPeek() {
        var choice = CardStopChoice()
        XCTAssertEqual(stop(choice, duoTurned, appState: 0), .peek)
        choice.appStateChanged(2)
        XCTAssertEqual(stop(choice, duoTurned, appState: 2), .half)
        choice.choose(.full)
        XCTAssertEqual(stop(choice, duoTurned, appState: 2), .full)
        choice.appStateChanged(0)
        XCTAssertEqual(stop(choice, duoTurned, appState: 0), .peek)
    }

    func testTheNextSessionOpensAtHalfAgain() {
        var choice = CardStopChoice()
        choice.appStateChanged(2)
        choice.choose(.peek)
        choice.appStateChanged(0)
        choice.appStateChanged(2)
        XCTAssertEqual(stop(choice, duoTurned, appState: 2), .half)
    }

    func testTheCloseButtonStopsTrackingAndRestsTheCardAtPeek() {
        var choice = CardStopChoice()
        choice.appStateChanged(2)
        choice.choose(.full)
        // The x ends the session, and the app drops to the board.
        choice.appStateChanged(0)
        XCTAssertEqual(choice.layout(width: 669, height: 951, appState: 0).stop, .peek)
        XCTAssertEqual(choice.layout(width: 669, height: 951, appState: 0).boardWidth, 466)
    }

    func testUnfoldingMapsHalfToSideBySideAndBack() {
        var choice = CardStopChoice()
        choice.appStateChanged(2)
        XCTAssertEqual(choice.layout(width: duoOpen.width, height: duoOpen.height, appState: 2).mode, .sideBySide)
        XCTAssertEqual(stop(choice, duoTurned, appState: 2), .half)
        XCTAssertEqual(choice.layout(width: duoOpen.width, height: duoOpen.height, appState: 2).mode, .sideBySide)
        XCTAssertEqual(stop(choice, duoTurned, appState: 2), .half)
    }

    func testTheChosenStopSurvivesASizeChange() {
        var choice = CardStopChoice()
        choice.appStateChanged(2)
        choice.choose(.full)
        XCTAssertEqual(choice.layout(width: duoOpen.width, height: duoOpen.height, appState: 2).mode, .sideBySide)
        XCTAssertEqual(stop(choice, duoTurned, appState: 2), .full)
    }

    func testADragSettlesAtTheNearestStop() {
        // At 669 wide the card's leading edge is 466 at Peek, 309 at Half, 0 at Full.
        XCTAssertEqual(settledStop(width: 669, height: 951, from: .half, predictedTranslation: 40), .half)
        XCTAssertEqual(settledStop(width: 669, height: 951, from: .half, predictedTranslation: 120), .peek)
        XCTAssertEqual(settledStop(width: 669, height: 951, from: .half, predictedTranslation: -200), .full)
        XCTAssertEqual(settledStop(width: 669, height: 951, from: .peek, predictedTranslation: -60), .peek)
    }

    func testAFlingCarriesTheCardPastTheNearestStop() {
        // A short drag with a fast release projects far past where the finger lifted.
        XCTAssertEqual(settledStop(width: 669, height: 951, from: .peek, predictedTranslation: -480), .full)
        XCTAssertEqual(settledStop(width: 669, height: 951, from: .full, predictedTranslation: 600), .peek)
    }

    func testTheGrabberOpensAndClosesTheCardOneStopAtATime() {
        XCTAssertEqual(openedStop(.peek), .half)
        XCTAssertEqual(openedStop(.half), .full)
        XCTAssertEqual(openedStop(.full), .full)
        XCTAssertEqual(closedStop(.full), .half)
        XCTAssertEqual(closedStop(.half), .peek)
        XCTAssertEqual(closedStop(.peek), .peek)
    }

    func testOnlyTrackingLocksTheBoardPickers() {
        XCTAssertTrue(boardPickersLocked(appState: 2))
        XCTAssertFalse(boardPickersLocked(appState: 0))
        XCTAssertFalse(boardPickersLocked(appState: 3))
    }

    func testAPickerTapWhileTrackingAsksToStop() {
        XCTAssertEqual(pickerTap(.station, appState: 2, currentMode: .train), .ask)
        XCTAssertEqual(pickerTap(.mode(.bus), appState: 2, currentMode: .train), .ask)
    }

    func testAPickerTapWhenIdleOpens() {
        for appState in [0, 3] {
            XCTAssertEqual(pickerTap(.station, appState: appState, currentMode: .train), .open)
            XCTAssertEqual(pickerTap(.mode(.bus), appState: appState, currentMode: .train), .open)
        }
    }

    func testATapOnTheShownModeChangesNothing() {
        for appState in [0, 2] {
            XCTAssertEqual(pickerTap(.mode(.train), appState: appState, currentMode: .train), .keep)
        }
    }

    func testAConfirmedPickerTapEndsTheSessionBeforeThePickerOpens() {
        XCTAssertEqual(confirmedPickerTap(appState: 2), PickerPlan(endSession: true))
    }

    func testAPickerTapConfirmedAfterTheSessionEndedOnlyOpens() {
        XCTAssertEqual(confirmedPickerTap(appState: 0), PickerPlan(endSession: false))
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

    func testABoardTapTracksWhenNothingIsTracked() {
        let dep = row("Basel SBB", 1_718_000_960, train: "2517")
        XCTAssertEqual(boardTap(dep, appState: 0, focused: nil), .track)
        XCTAssertEqual(boardTap(dep, appState: 3, focused: focused("Luzern", train: "2515")), .track)
    }

    func testABoardTapOnTheTrackedRowKeepsTheSession() {
        let tracked = focused("Luzern", train: "2515")
        XCTAssertEqual(boardTap(row("Luzern", 1_718_000_360, train: "2515"), appState: 2, focused: tracked), .keep)
    }

    func testABoardTapOnATwinOfTheTrackedTrainAsks() {
        let tracked = focused("Luzern", train: "2515")
        XCTAssertEqual(boardTap(row("Luzern", 1_718_000_360, train: "92515"), appState: 2, focused: tracked), .ask)
    }

    func testABoardTapOnAnotherRowAsks() {
        let tracked = focused("Luzern", train: "2515")
        XCTAssertEqual(boardTap(row("Luzern", 1_718_000_960, train: "2517"), appState: 2, focused: tracked), .ask)
    }

    func testAConfirmedSwitchEndsTheTrackedSessionFirst() {
        let tracked = focused("Luzern", train: "2515")
        let plan = confirmedSwitch(row("Luzern", 1_718_000_960, train: "2517"), appState: 2, focused: tracked)
        XCTAssertEqual(plan, SwitchPlan(endDepTs: 1_718_000_360))
    }

    func testASwitchConfirmedAfterTheSessionEndedOnlyTracks() {
        let plan = confirmedSwitch(row("Luzern", 1_718_000_960, train: "2517"), appState: 0, focused: nil)
        XCTAssertEqual(plan, SwitchPlan(endDepTs: nil))
    }

    func testASwitchToTheNowTrackedRowDoesNothing() {
        let tracked = focused("Luzern", train: "2515")
        XCTAssertNil(confirmedSwitch(row("Luzern", 1_718_000_360, train: "2515"), appState: 2, focused: tracked))
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

    // The iPhone Duo inner display turned (2007x2853 px at 3x).
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
        ScrollView {
            VStack(spacing: 16) {
                Text("Luzern").font(.title2.weight(.bold))
                Text("6 min").font(.system(size: 64, weight: .bold, design: .rounded))
                TrackingBarView(schedBuf: 4, effectBuf: 5, hasGPS: true)
            }
            .padding(16)
        }
    }

    private var summary: some View {
        TrackingPeekSummary(lineNumber: "IR15", lineColour: AppColors.linePill("IR15", mode: .train),
                            destination: "Luzern", countdown: "6 min", countdownColour: AppColors.minutesSoon)
    }

    private func assertPanes(_ detail: some View, _ name: String, size: CGSize,
                             styles: [(String, UIUserInterfaceStyle)], tracked: Int?, stop: CardStop? = nil,
                             testName: String = #function, line: UInt = #line) {
        let layout = paneLayout(width: size.width, height: size.height, appState: tracked == nil ? 0 : 2, stop: stop)
        let view = AdaptivePanes(layout: layout, showsTracking: tracked != nil) {
            self.board(tracked: tracked)
        } tracking: {
            detail
        } summary: {
            self.summary
        } hint: {
            TrackingPaneHint()
        }
        .frame(width: size.width, height: size.height)
        .background(Color(uiColor: .systemBackground))
        for (suffix, style) in styles {
            assertSnapshot(
                of: view,
                as: .image(precision: 0.99, perceptualPrecision: 0.98,
                           layout: .fixed(width: size.width, height: size.height),
                           traits: .init(userInterfaceStyle: style)),
                named: "\(name)_\(suffix)", testName: testName, line: line
            )
        }
    }

    private let bothStyles: [(String, UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

    // The board keeps 466pt beside the Peek card, so its longest destinations read in full.
    func testCardAtPeekWhileIdleAtDuoTurnedSize() {
        assertPanes(EmptyView(), "card_peek_idle", size: duoInner, styles: bothStyles, tracked: nil)
    }

    func testCardAtPeekWhileTrackingAtDuoTurnedSize() {
        assertPanes(tracking, "card_peek_tracking", size: duoInner, styles: bothStyles, tracked: trackedIr15, stop: .peek)
    }

    func testCardAtHalfAtDuoTurnedSize() {
        assertPanes(tracking, "card_half", size: duoInner, styles: bothStyles, tracked: trackedIr15)
    }

    func testCardAtFullAtDuoTurnedSize() {
        assertPanes(tracking, "card_full", size: duoInner, styles: [("light", .light)], tracked: trackedIr15, stop: .full)
    }

    func testSideBySideIdleAtDuoOpenSize() {
        assertPanes(EmptyView(), "side_idle", size: duoOpen, styles: bothStyles, tracked: nil)
    }

    func testSideBySideTrackingAtDuoOpenSize() {
        assertPanes(tracking, "side_tracking", size: duoOpen, styles: bothStyles, tracked: trackedIr15)
    }

    // The folded Duo and a large phone turned sideways: too short for a second
    // pane, so the board and tracking each take the window.
    private let foldedLandscape = CGSize(width: 678, height: 466)
    private let largeLandscape = CGSize(width: 956, height: 440)

    func testShortLandscapeShowsTheBoardAlone() {
        assertPanes(EmptyView(), "short_678_board", size: foldedLandscape, styles: [("light", .light)], tracked: nil)
        assertPanes(EmptyView(), "short_956_board", size: largeLandscape, styles: [("light", .light)], tracked: nil)
    }

    func testShortLandscapeShowsTrackingAlone() {
        assertPanes(tracking, "short_678_tracking", size: foldedLandscape, styles: [("light", .light)], tracked: trackedIr15)
        assertPanes(tracking, "short_956_tracking", size: largeLandscape, styles: [("light", .light)], tracked: trackedIr15)
    }
}
