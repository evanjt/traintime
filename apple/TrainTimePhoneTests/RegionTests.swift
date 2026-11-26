import CoreLocation
import XCTest
@testable import TrainTimePhone

final class RegionTests: XCTestCase {
    func testSharedPointsMapToTheSameRegionOnEveryPlatform() {
        XCTAssertEqual(Region.at(lat: -37.8213, lon: 145.0364)?.id, Region.melbourne.id)
        XCTAssertEqual(Region.at(lat: 46.9480, lon: 7.4474)?.id, Region.switzerland.id)
        XCTAssertNil(Region.at(lat: -38.1499, lon: 144.3617))
        XCTAssertNil(Region.at(lat: -33.8688, lon: 151.2093))
    }

    func testStationIdPicksItsRegion() {
        XCTAssertEqual(Region.forStationId("au-vic-1080")?.id, Region.melbourne.id)
        XCTAssertEqual(Region.forStationId("8503000")?.id, Region.switzerland.id)
        XCTAssertNil(Region.forStationId(nil))
        XCTAssertNil(Region.forStationId(""))
    }

    func testPrefixesCarryNoSeparatorUsedInPayloads() {
        for region in Region.all {
            XCTAssertFalse(region.idPrefix.contains(":"))
            XCTAssertFalse(region.idPrefix.contains(","))
        }
    }

    func testSwissOnlyFeaturesFollowTheRegionFlags() {
        XCTAssertTrue(Region.hasFormation(stationId: "8503000"))
        XCTAssertFalse(Region.hasFormation(stationId: "au-vic-1080"))
        XCTAssertFalse(Region.hasFormation(stationId: nil))
    }

    func testCoveredFixWithAnEmptyBoardSearches() {
        XCTAssertEqual(CoverageGate.onFix(lat: -37.8213, lon: 145.0364, hasStations: false), .search)
        XCTAssertEqual(CoverageGate.onFix(lat: 46.9480, lon: 7.4474, hasStations: false), .search)
    }

    func testUncoveredFixWithAnEmptyBoardShowsOutOfCoverage() {
        XCTAssertEqual(CoverageGate.onFix(lat: -33.8688, lon: 151.2093, hasStations: false), .outOfCoverage)
    }

    func testUncoveredFixKeepsABoardThatHasStations() {
        XCTAssertEqual(CoverageGate.onFix(lat: -33.8688, lon: 151.2093, hasStations: true), .search)
    }
}

final class RegionClockTests: XCTestCase {
    private var savedZone: TimeZone!

    override func setUp() {
        super.setUp()
        savedZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Europe/Zurich")!
    }

    override func tearDown() {
        NSTimeZone.default = savedZone
        super.tearDown()
    }

    // 2026-11-23 10:38 UTC
    private let departure = 1_795_430_280

    func testDepartureReadsInTheStationZoneNotTheDeviceZone() {
        XCTAssertEqual(Region.clockTime(departure, stationId: "au-vic-1080"), "21:38")
        XCTAssertEqual(Region.clockTime(departure, stationId: "8503000"), "11:38")
    }

    func testUnknownStationReadsInTheDeviceZone() {
        let device = DateFormatter()
        device.dateFormat = "HH:mm"
        device.timeZone = .current
        XCTAssertEqual(Region.clockTime(departure, stationId: nil),
                       device.string(from: Date(timeIntervalSince1970: TimeInterval(departure))))
    }

    func testServiceDateFollowsTheStationZone() {
        // 2026-11-22 14:00 UTC: already the 23rd in Melbourne, still the 22nd in Bern.
        let date = Date(timeIntervalSince1970: 1_795_356_000)
        XCTAssertEqual(Region.serviceDate(date, stationId: "au-vic-1080"), "2026-11-23")
        XCTAssertEqual(Region.serviceDate(date, stationId: "8503000"), "2026-11-22")
    }
}
