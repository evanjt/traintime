import XCTest
@testable import TrainTimePhone

final class LiveActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testFarDepartureStaysFreshForOnePayload() {
        let departure = now.addingTimeInterval(3600)
        XCTAssertEqual(
            LiveActivityTiming.staleDate(effectiveDeparture: departure, now: now),
            now.addingTimeInterval(LiveActivityTiming.freshFor))
    }

    // A suspended app sends nothing more, so the card must re-render on its own
    // the moment the train leaves.
    func testNearDepartureGoesStaleAtTheDeparture() {
        let departure = now.addingTimeInterval(120)
        XCTAssertEqual(LiveActivityTiming.staleDate(effectiveDeparture: departure, now: now), departure)
    }

    func testDepartedTrainIsStaleAlready() {
        let departure = now.addingTimeInterval(-30)
        XCTAssertLessThanOrEqual(LiveActivityTiming.staleDate(effectiveDeparture: departure, now: now), now)
    }

    func testStopRequestAppliesOnce() {
        let defaults = UserDefaults(suiteName: "LiveActivityTests")!
        defaults.removePersistentDomain(forName: "LiveActivityTests")
        XCTAssertFalse(TrackingStopRequest.take(defaults))
        TrackingStopRequest.record(defaults)
        XCTAssertTrue(TrackingStopRequest.take(defaults))
        XCTAssertFalse(TrackingStopRequest.take(defaults))
    }

    func testBackKeepsTheSessionWithBackgroundTrackingOn() {
        XCTAssertEqual(TrackingSessionLogic.back(backgroundTracking: true), .park)
    }

    // With background tracking off no Live Activity runs, so there is nothing to keep.
    func testBackEndsTheSessionWithBackgroundTrackingOff() {
        XCTAssertEqual(TrackingSessionLogic.back(backgroundTracking: false), .end)
    }

    func testStopOnTheTrackingScreenEndsTheImmersiveSession() {
        XCTAssertEqual(TrackingSessionLogic.stop(immersive: true, parked: false), .endImmersive)
    }

    func testStopFromTheBoardEndsTheParkedSession() {
        XCTAssertEqual(TrackingSessionLogic.stop(immersive: false, parked: true), .endParked)
    }

    func testStopWithNoSessionDoesNothing() {
        XCTAssertEqual(TrackingSessionLogic.stop(immersive: false, parked: false), .nothing)
    }
}
