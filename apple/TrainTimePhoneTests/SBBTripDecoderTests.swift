import XCTest
@testable import TrainTimePhone

/// Fixture captured live from https://a.sbbmobile.ch/s/SA5YK2Z1 on 2026-07-05:
/// walk (GPS point → Sion) → IR 90 1820 (Sion 13:02 → Lausanne 14:12) →
/// walk (→ Lausanne, gare). Frozen so tests never touch the network.
/// Mirror of android SbbTripDecoderTest.kt.
final class SBBTripDecoderTests: XCTestCase {
    private static let fixtureBlob: String = {
        let url = Bundle(for: SBBTripDecoderTests.self).url(forResource: "sbb_trip_fixture", withExtension: "txt")!
        return try! String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    private let rideDep = 1783249320 // 2026-07-05 13:02 Europe/Zurich (CEST)
    private let rideArr = 1783253520

    private func departure(
        trainNumber: String? = "1820",
        timestamp: Int? = 1783249320,
        lineNumber: String = "IR90",
        destination: String = "Genève-Aéroport"
    ) -> Departure {
        Departure(
            destination: destination,
            minutesUntil: 10,
            departureTimestamp: timestamp,
            delay: 0,
            platform: "3",
            platformChanged: false,
            lineNumber: lineNumber,
            category: "IR",
            trainNumber: trainNumber,
            operatorRef: "11"
        )
    }

    func testFindRecognisesShortLinkAmidShareText() {
        let link = SBBShareLink.find(in: "Check out my trip! https://a.sbbmobile.ch/s/SA5YK2Z1 sent from SBB Mobile")
        XCTAssertEqual(link, .short("https://a.sbbmobile.ch/s/SA5YK2Z1"))
    }

    func testFindRecognisesReconAndTripIdLinks() {
        XCTAssertEqual(
            SBBShareLink.find(in: "sbbmobile://trip?recon=\(Self.fixtureBlob)"),
            .blob(Self.fixtureBlob)
        )
        XCTAssertEqual(
            SBBShareLink.find(in: "see https://www.sbb.ch/en/trip?tripId=\(Self.fixtureBlob) ok"),
            .blob(Self.fixtureBlob)
        )
    }

    func testFindReturnsNilOnUnrelatedText() {
        XCTAssertNil(SBBShareLink.find(in: "meet me at the station at 13:02, https://example.com/x"))
    }

    func testDecodesFrozenFixtureIntoThreeLegs() throws {
        let route = try SBBTripDecoder.decode(blob: Self.fixtureBlob)
        XCTAssertEqual(route.legs.count, 3)

        let walkIn = route.legs[0]
        XCTAssertEqual(walkIn.type, .walk)
        XCTAssertNil(walkIn.originId)
        XCTAssertEqual(walkIn.destName, "Sion")
        XCTAssertEqual(walkIn.destId, "8501506")
        XCTAssertEqual(walkIn.depTs, 1783248600)

        let ride = route.legs[1]
        XCTAssertEqual(ride.type, .ride)
        XCTAssertEqual(ride.originId, "8501506")
        XCTAssertEqual(ride.originName, "Sion")
        XCTAssertEqual(ride.destId, "8501120")
        XCTAssertEqual(ride.destName, "Lausanne")
        XCTAssertEqual(ride.depTs, rideDep)
        XCTAssertEqual(ride.arrTs, rideArr)
        XCTAssertEqual(ride.category, "IR")
        XCTAssertEqual(ride.lineNumber, "90")
        XCTAssertEqual(ride.trainNumber, "1820")
        XCTAssertEqual(ride.originLat!, 46.227549, accuracy: 1e-9)
        XCTAssertEqual(ride.originLon!, 7.359199, accuracy: 1e-9)

        let walkOut = route.legs[2]
        XCTAssertEqual(walkOut.type, .walk)
        XCTAssertEqual(walkOut.destName, "Lausanne, gare")
        XCTAssertEqual(walkOut.destId, "8592050")
        XCTAssertEqual(walkOut.arrTs, 1783253820)

        XCTAssertEqual(route.finalDestinationName, "Lausanne, gare")
    }

    func testWinterTimesConvertWithCETOffset() {
        // 2026-12-05 13:02 +01:00
        XCTAssertEqual(SBBTripDecoder.epoch(fromLocal: "202612051302"), 1796472120)
    }

    func testTargetRideLegIndexPicksTheCatchableRide() throws {
        let route = try SBBTripDecoder.decode(blob: Self.fixtureBlob)
        XCTAssertEqual(route.targetRideLegIndex(now: rideDep - 3600), 1)
        XCTAssertEqual(route.targetRideLegIndex(now: rideDep + 60), 1) // grace window
        XCTAssertNil(route.targetRideLegIndex(now: rideDep + 61))
    }

    func testMatchDeparturePrefersExactTrainNumberAndTimestamp() throws {
        let leg = try SBBTripDecoder.decode(blob: Self.fixtureBlob).legs[1]
        let exact = departure()
        let decoy = departure(trainNumber: "1822", timestamp: rideDep + 1800)
        XCTAssertEqual(matchDeparture([decoy, exact], leg: leg)?.trainNumber, "1820")
    }

    func testMatchDepartureFallsBackToNormalisedLineWithinAMinute() throws {
        let leg = try SBBTripDecoder.decode(blob: Self.fixtureBlob).legs[1]
        let board = [departure(trainNumber: nil, timestamp: rideDep + 30)]
        XCTAssertNotNil(matchDeparture(board, leg: leg))
    }

    func testMatchDepartureNeverMatchesOnDestinationAlone() throws {
        let leg = try SBBTripDecoder.decode(blob: Self.fixtureBlob).legs[1]
        let wrongTrain = departure(
            trainNumber: "9999", timestamp: rideDep + 3600,
            lineNumber: "IC5", destination: "Lausanne"
        )
        XCTAssertNil(matchDeparture([wrongTrain], leg: leg))
    }

    func testUnsupportedVersionIsRejected() {
        let blob = "4XA" + Self.fixtureBlob.dropFirst(3)
        XCTAssertThrowsError(try SBBTripDecoder.decode(blob: blob)) { error in
            XCTAssertEqual(error as? SBBDecodeError, .unsupportedVersion)
        }
    }

    func testTruncatedBlobIsMalformed() {
        XCTAssertThrowsError(try SBBTripDecoder.decode(blob: String(Self.fixtureBlob.prefix(40)))) { error in
            XCTAssertEqual(error as? SBBDecodeError, .malformed)
        }
    }

    func testExtractBlobFindsTheSplashAnchor() {
        let html = "<a id=\"appLink\" href=\"sbbmobile://trip?recon=\(Self.fixtureBlob)\">Open</a>"
        XCTAssertEqual(SBBTripDecoder.extractBlob(fromHTML: html), Self.fixtureBlob)
    }
}
