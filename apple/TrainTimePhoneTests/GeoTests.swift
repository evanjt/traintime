import CoreLocation
import XCTest
@testable import TrainTimePhone

final class GeoTests: XCTestCase {
    func testDistanceBetweenRealStationsIsDeterministicAndSymmetric() {
        // Place de la Planta -> Gare de Sion, ~376 m by the flat-earth model.
        let planta = CLLocationCoordinate2D(latitude: 46.2306, longitude: 7.3576)
        let sion = CLLocationCoordinate2D(latitude: 46.2275, longitude: 7.3596)
        XCTAssertEqual(GeoUtils.haversineDistance(from: planta, to: sion), 376.0, accuracy: 1.0)
        XCTAssertEqual(
            GeoUtils.haversineDistance(from: sion, to: planta),
            GeoUtils.haversineDistance(from: planta, to: sion),
            accuracy: 0.001,
        )
    }

    func testWalkInfoFormatting() {
        XCTAssertEqual(GeoUtils.formatWalkInfo(distanceMeters: 200), "2 min walk - 200m")
        XCTAssertEqual(GeoUtils.formatWalkInfo(distanceMeters: 50), "<1 min walk - 50m")
        XCTAssertEqual(GeoUtils.formatWalkInfo(distanceMeters: 100, walkTimeSeconds: 300), "5 min walk - 100m")
    }

    func testWalkMinutesDeriveFromDistance() {
        XCTAssertEqual(GeoUtils.walkMinutes(distanceMeters: 376), 376.0 / 83.0, accuracy: 0.001)
    }
}

final class LocationFixTests: XCTestCase {
    func testFreshFixIsLive() {
        XCTAssertEqual(LocationFix.verdict(age: 0.3, horizontalAccuracy: 35, holdingCoordinate: false), .live)
        XCTAssertEqual(LocationFix.verdict(age: 4.9, horizontalAccuracy: 65, holdingCoordinate: true), .live)
    }

    func testReplayedFixWithNothingHeldIsCached() {
        XCTAssertEqual(LocationFix.verdict(age: 600, horizontalAccuracy: 10, holdingCoordinate: false), .cached)
    }

    func testReplayedFixNeverReplacesAHeldCoordinate() {
        XCTAssertEqual(LocationFix.verdict(age: 600, horizontalAccuracy: 10, holdingCoordinate: true), .ignore)
    }

    func testInvalidAccuracyIsIgnored() {
        XCTAssertEqual(LocationFix.verdict(age: 0, horizontalAccuracy: -1, holdingCoordinate: false), .ignore)
    }

    func testCachedBoardWaitsForTheRequestInFlight() {
        XCTAssertEqual(LocationFix.cachedBoardOnLiveFix(requestInFlight: true, movedFromSearch: true), .waitForRequest)
    }

    func testCachedBoardFromTheSamePlaceIsKept() {
        XCTAssertEqual(LocationFix.cachedBoardOnLiveFix(requestInFlight: false, movedFromSearch: false), .keep)
    }

    func testCachedBoardFromElsewhereIsRefetched() {
        XCTAssertEqual(LocationFix.cachedBoardOnLiveFix(requestInFlight: false, movedFromSearch: true), .refetch)
        XCTAssertEqual(LocationFix.cachedBoardOnLiveFix(requestInFlight: false, movedFromSearch: nil), .refetch)
    }
}
