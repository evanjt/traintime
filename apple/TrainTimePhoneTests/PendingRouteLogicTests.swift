import XCTest
@testable import TrainTimePhone

/// Mirror of android PendingRouteLogicTest.kt (frozen clock).
final class PendingRouteLogicTests: XCTestCase {
    private let now = 1_800_000_000

    private func ride(dep: Int, arr: Int? = nil, train: String? = "1820") -> RouteLeg {
        RouteLeg(
            type: .ride,
            originId: "8501506", originName: "Sion",
            originLat: 46.2276, originLon: 7.3607,
            destId: "8501120", destName: "Lausanne",
            depTs: dep, arrTs: arr ?? dep + 3600,
            category: "IR", lineNumber: "90", trainNumber: train
        )
    }

    // A ride starting outside Switzerland: no departure board, so untrackable.
    private func foreignRide(dep: Int, arr: Int? = nil) -> RouteLeg {
        RouteLeg(
            type: .ride,
            originId: "8300000", originName: "Torino",
            originLat: 45.0703, originLon: 7.6869,
            destId: "8300001", destName: "Milano",
            depTs: dep, arrTs: arr ?? dep + 3600,
            category: "EC", lineNumber: "40", trainNumber: "9"
        )
    }

    private func walk(dep: Int, arr: Int) -> RouteLeg {
        RouteLeg(type: .walk, originName: "somewhere", destName: "Sion", depTs: dep, arrTs: arr)
    }

    private func route(_ legs: [RouteLeg], cursor: Int = 0, status: String = PendingRoute.statusSaved, muted: [Int] = []) -> PendingRoute {
        PendingRoute(
            id: "r1", legs: legs, finalDestination: "Lausanne",
            cursor: cursor, status: status, createdTs: now - 3600,
            sourceUrl: nil, mutedLegIndices: muted.isEmpty ? nil : muted
        )
    }

    func testNormalizeKeepsAFutureLegUntouched() {
        let r = route([ride(dep: now + 7200)])
        XCTAssertEqual(PendingRouteLogic.normalize(r, now: now), r)
    }

    func testNormalizeSkipsWalksAndMissedRidesToTheNextViableLeg() {
        let r = route([
            walk(dep: now - 7200, arr: now - 7000),
            ride(dep: now - 7000, arr: now - 3600, train: "1"),
            ride(dep: now + 3600, train: "2"),
        ])
        let normalized = PendingRouteLogic.normalize(r, now: now)!
        XCTAssertEqual(normalized.cursor, 2)
        XCTAssertEqual(normalized.currentLeg?.trainNumber, "2")
    }

    func testNormalizeExpiresWhenEveryRideHasLeft() {
        XCTAssertNil(PendingRouteLogic.normalize(route([ride(dep: now - 7200), ride(dep: now - 3600)]), now: now))
    }

    func testNormalizeIsIdempotent() {
        let r = route([ride(dep: now - 7000, train: "1"), ride(dep: now + 3600, train: "2")])
        let once = PendingRouteLogic.normalize(r, now: now)!
        XCTAssertEqual(PendingRouteLogic.normalize(once, now: now), once)
    }

    func testNormalizeResetsTrackingStatusWhenItAdvances() {
        let r = route(
            [ride(dep: now - 7000, train: "1"), ride(dep: now + 3600, train: "2")],
            status: PendingRoute.statusTracking
        )
        XCTAssertEqual(PendingRouteLogic.normalize(r, now: now)?.status, PendingRoute.statusSaved)
    }

    func testNotifyTsUsesTheFifteenMinuteFloor() {
        let dep = now + 7200
        XCTAssertEqual(PendingRouteLogic.notifyTs(route([ride(dep: dep)])), dep - 15 * 60)
    }

    func testNotifyTsStretchesForALongPrecedingWalk() {
        let dep = now + 7200
        let r = route([walk(dep: dep - 1500, arr: dep - 60), ride(dep: dep)], cursor: 1)
        // 24 min walk + 5 min margin beats the 15 min floor.
        XCTAssertEqual(PendingRouteLogic.notifyTs(r), dep - (1440 + 300))
    }

    func testConnectionLegUsesTheShorterConnectionLead() {
        let dep = now + 7200
        // First ride already departed, cursor on the second ride (a connection).
        let r = route([
            ride(dep: now - 3600, train: "1"),
            walk(dep: dep - 120, arr: dep - 30),
            ride(dep: dep, train: "2"),
        ], cursor: 2)
        XCTAssertEqual(PendingRouteLogic.notifyTs(r), dep - 3 * 60)
    }

    func testLeadsAreConfigurableAndIndependent() {
        let dep = now + 7200
        XCTAssertEqual(PendingRouteLogic.notifyTs(route([ride(dep: dep)]), savedLeadSec: 10 * 60), dep - 10 * 60)
        let connection = route([ride(dep: now - 3600, train: "1"), ride(dep: dep, train: "2")], cursor: 1)
        XCTAssertEqual(PendingRouteLogic.notifyTs(connection, connectionLeadSec: 4 * 60), dep - 4 * 60)
    }

    func testDistanceAddsWalkTimeToTheBuffer() {
        let dep = now + 7200
        // 830 m ≈ 10 min walk at 83 m/min, + 5 min buffer = 15 min lead.
        XCTAssertEqual(PendingRouteLogic.notifyTs(route([ride(dep: dep)]), savedLeadSec: 5 * 60, userDistanceMeters: 830), dep - (10 + 5) * 60)
    }

    func testDistanceLeadIsCapped() {
        let dep = now + 100_000
        XCTAssertEqual(PendingRouteLogic.notifyTs(route([ride(dep: dep)]), userDistanceMeters: 100_000), dep - PendingRouteLogic.maxLeadSec)
    }

    func testNilDistanceKeepsTheStaticLead() {
        let dep = now + 7200
        XCTAssertEqual(PendingRouteLogic.notifyTs(route([ride(dep: dep)]), userDistanceMeters: nil), dep - 15 * 60)
    }

    func testConnectionLegIgnoresDistance() {
        let dep = now + 7200
        let r = route([ride(dep: now - 3600, train: "1"), ride(dep: dep, train: "2")], cursor: 1)
        XCTAssertEqual(PendingRouteLogic.notifyTs(r, userDistanceMeters: 5000), dep - 3 * 60)
    }

    func testIsConnectionLegTrueOnlyPastTheFirstRide() {
        XCTAssertFalse(PendingRouteLogic.isConnectionLeg(route([ride(dep: now + 3600)])))
        let r = route([ride(dep: now - 3600, train: "1"), ride(dep: now + 3600, train: "2")], cursor: 1)
        XCTAssertTrue(PendingRouteLogic.isConnectionLeg(r))
    }

    func testIsResumableOnlyInsideTheWindow() {
        XCTAssertTrue(PendingRouteLogic.isResumable(route([ride(dep: now + 44 * 60)]), now: now))
        XCTAssertFalse(PendingRouteLogic.isResumable(route([ride(dep: now + 46 * 60)]), now: now))
        XCTAssertFalse(PendingRouteLogic.isResumable(route([ride(dep: now - 200)]), now: now))
    }

    func testMutedCurrentLegGetsNoReminderAndNoResumeOffer() {
        let r = route([ride(dep: now + 30 * 60)], muted: [0])
        XCTAssertNil(PendingRouteLogic.notifyTs(r))
        XCTAssertFalse(PendingRouteLogic.isResumable(r, now: now))
    }

    func testUntrackableCurrentLegGetsNoReminderAndNoResumeOffer() {
        let r = route([foreignRide(dep: now + 30 * 60)])
        XCTAssertNil(PendingRouteLogic.notifyTs(r))
        XCTAssertFalse(PendingRouteLogic.isResumable(r, now: now))
    }

    func testAWalkCurrentLegGetsNoReminderAndNoResumeOffer() {
        // A route whose cursor lands on a walk leg has no ride to track.
        let r = route([walk(dep: now + 30 * 60, arr: now + 32 * 60)], cursor: 0)
        XCTAssertNil(PendingRouteLogic.notifyTs(r))
        XCTAssertFalse(PendingRouteLogic.isResumable(r, now: now))
    }

    func testUnmutingALegRestoresTheReminder() {
        let r = route([ride(dep: now + 30 * 60)])
        XCTAssertEqual(PendingRouteLogic.notifyTs(r), now + 30 * 60 - 15 * 60)
    }

    func testFingerprintStableForTheSameFirstRide() {
        let a = route([walk(dep: now, arr: now + 100), ride(dep: now + 3600)])
        let b = route([ride(dep: now + 3600)])
        XCTAssertEqual(PendingRouteLogic.fingerprint(a.legs), PendingRouteLogic.fingerprint(b.legs))
    }

    func testAdvanceMovesToTheNextLegWhenTheTrackedLegDeparted() {
        let dep = now - 120
        let r = route(
            [ride(dep: dep, train: "1"), walk(dep: now - 60, arr: now + 300), ride(dep: now + 3600, train: "2")],
            status: PendingRoute.statusTracking
        )
        let advanced = PendingRouteLogic.advancedAfterTracking(r, endedDepTs: dep, now: now)!
        XCTAssertEqual(advanced.cursor, 2)
        XCTAssertEqual(advanced.status, PendingRoute.statusSaved)
    }

    func testAdvanceExpiresASingleLegRouteAfterDeparture() {
        let dep = now - 120
        let r = route([ride(dep: dep)], status: PendingRoute.statusTracking)
        XCTAssertNil(PendingRouteLogic.advancedAfterTracking(r, endedDepTs: dep, now: now))
    }

    func testEarlyManualExitRevertsToSavedOnTheSameLeg() {
        let dep = now + 3600
        let r = route([ride(dep: dep)], status: PendingRoute.statusTracking)
        let reverted = PendingRouteLogic.advancedAfterTracking(r, endedDepTs: dep, now: now)!
        XCTAssertEqual(reverted.cursor, 0)
        XCTAssertEqual(reverted.status, PendingRoute.statusSaved)
    }

    func testUnrelatedTrackingEndLeavesPendingUntouched() {
        let r = route([ride(dep: now + 3600)], status: PendingRoute.statusTracking)
        XCTAssertEqual(PendingRouteLogic.advancedAfterTracking(r, endedDepTs: now + 999, now: now), r)
        let saved = route([ride(dep: now + 3600)])
        XCTAssertEqual(PendingRouteLogic.advancedAfterTracking(saved, endedDepTs: now + 3600, now: now), saved)
    }
}
