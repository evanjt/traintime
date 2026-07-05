import XCTest
@testable import TrainTimePhone

// Mirrors the Android ReviewGateTest so the timed review ask behaves
// identically on both phones.
final class ReviewGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private var oldEnough: Date { now.addingTimeInterval(-ReviewGate.minAge) }

    private func prompt(
        trackCount: Int = 3,
        promptedVersion: String = "",
        currentVersion: String = "0.5.0",
        firstLaunch: Date? = nil,
        snoozeUntil: Date? = nil,
        optedOut: Bool = false
    ) -> Bool {
        ReviewGate.shouldPrompt(
            trackCount: trackCount,
            promptedVersion: promptedVersion,
            currentVersion: currentVersion,
            firstLaunch: firstLaunch ?? oldEnough,
            snoozeUntil: snoozeUntil,
            optedOut: optedOut,
            now: now
        )
    }

    func testBelowThresholdNeverPrompts() {
        XCTAssertFalse(prompt(trackCount: 2))
    }

    func testAtThresholdPrompts() {
        XCTAssertTrue(prompt(trackCount: 3))
    }

    func testAlreadyPromptedThisVersionDoesNotPromptAgain() {
        XCTAssertFalse(prompt(trackCount: 9, promptedVersion: "0.5.0"))
    }

    func testPromptsAgainAfterVersionBump() {
        XCTAssertTrue(prompt(trackCount: 9, promptedVersion: "0.4.2"))
    }

    func testYoungInstallDoesNotPrompt() {
        XCTAssertFalse(prompt(firstLaunch: oldEnough.addingTimeInterval(1)))
    }

    func testInstallExactlyAtMinimumAgePrompts() {
        XCTAssertTrue(prompt(firstLaunch: oldEnough))
    }

    func testMissingFirstLaunchNeverPrompts() {
        XCTAssertFalse(ReviewGate.shouldPrompt(
            trackCount: 9, promptedVersion: "", currentVersion: "0.5.0",
            firstLaunch: nil, snoozeUntil: nil, optedOut: false, now: now
        ))
    }

    func testActiveSnoozeDoesNotPrompt() {
        XCTAssertFalse(prompt(snoozeUntil: now.addingTimeInterval(1)))
    }

    func testExpiredSnoozePrompts() {
        XCTAssertTrue(prompt(snoozeUntil: now))
    }

    func testOptOutWinsOverEverything() {
        XCTAssertFalse(prompt(trackCount: 99, optedOut: true))
    }
}
