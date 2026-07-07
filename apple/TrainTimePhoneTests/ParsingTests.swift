import XCTest
@testable import TrainTimePhone

// Parses the same API JSON shapes as the Android MockWebServer tests, via the
// static from(json:) parsers, no network.
final class ParsingTests: XCTestCase {
    func testStationParsesWithEmbeddedDepartures() {
        let json: [String: Any] = [
            "id": "8501120", "name": "Lausanne", "lat": 46.516, "lon": 6.629, "dist": 250.0,
            "departures": [
                ["to": "Brig", "category": "IC", "number": "IC8", "departure": 1_718_000_600, "delay": 2, "platform": "3"],
            ],
        ]
        let station = Station.from(json: json, mode: .train)!
        XCTAssertEqual(station.id, "8501120")
        XCTAssertEqual(station.name, "Lausanne")
        XCTAssertEqual(station.dist!, 250.0, accuracy: 0.001)
        XCTAssertEqual(station.mode, .train)
        let dep = station.embeddedDepartures!.first!
        XCTAssertEqual(dep.destination, "Brig")
        XCTAssertEqual(dep.lineNumber, "IC8")
        XCTAssertEqual(dep.departureTimestamp, 1_718_000_600)
        XCTAssertEqual(dep.delay, 2)
    }

    func testStationWithoutIdIsNil() {
        XCTAssertNil(Station.from(json: ["name": "x"], mode: .train))
    }

    func testDepartureParsesFieldsAndPlatformChange() {
        let dep = Departure.from(json: [
            "to": "Genève", "number": "IR90", "departure": 1_718_000_720, "platform": "1", "platformChanged": true,
        ])
        XCTAssertEqual(dep.destination, "Genève")
        XCTAssertEqual(dep.lineNumber, "IR90")
        XCTAssertEqual(dep.departureTimestamp, 1_718_000_720)
        XCTAssertTrue(dep.platformChanged)
        XCTAssertEqual(dep.delay, 0)
    }

    private func coppetDep(trainNumber: String?, delay: Int? = nil, platform: String = "2", departure: Int = 1_783_171_320) -> Departure {
        var json: [String: Any] = ["to": "Coppet", "category": "R", "number": "RL4", "departure": departure, "platform": platform]
        if let trainNumber { json["trainNumber"] = trainNumber }
        if let delay { json["delay"] = delay }
        return Departure.from(json: json)
    }

    func testStableIdIncludesTrainNumberAndToleratesNil() {
        XCTAssertEqual(coppetDep(trainNumber: "23153").stableId, "1783171320|RL4|Coppet|23153")
        XCTAssertEqual(coppetDep(trainNumber: nil).stableId, "1783171320|RL4|Coppet|")
    }

    // Scenario: OJP publishes the same train under two journey numbers
    // (RL4 → Coppet as 23153 and 93153); only one carries the live delay.
    // Expected behaviour: one row survives, the delay-bearing one,
    // regardless of input order.
    func testDedupeCollapsesTwinPublicationsKeepingDelayBearingRow() {
        let planned = coppetDep(trainNumber: "23153")
        let tracked = coppetDep(trainNumber: "93153", delay: 1)
        for input in [[planned, tracked], [tracked, planned]] {
            let out = input.dedupedForDisplay()
            XCTAssertEqual(out.count, 1)
            XCTAssertEqual(out.first?.trainNumber, "93153")
            XCTAssertEqual(out.first?.delay, 1)
        }
    }

    func testDedupeKeepsRowsAPassengerCanTellApart() {
        let quayOne = coppetDep(trainNumber: "23153", platform: "1")
        let quayTwo = coppetDep(trainNumber: "93153", platform: "2")
        let laterTrain = coppetDep(trainNumber: "23155", departure: 1_783_171_380)
        let out = [quayOne, quayTwo, laterTrain].dedupedForDisplay()
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(Set(out.map(\.stableId)).count, 3)
    }

    func testFormationParsesWagons() {
        let json: [String: Any] = [
            "track": "3", "sectors": ["A", "B"],
            "wagons": [
                ["position": 1, "number": 101, "class": 2, "sector": "A", "features": ["wheelchair"]],
                ["position": 2, "number": 102, "class": 1, "sector": "B"],
            ],
        ]
        let f = Formation.from(json: json)!
        XCTAssertEqual(f.track, "3")
        XCTAssertEqual(f.sectors, ["A", "B"])
        XCTAssertEqual(f.wagons.count, 2)
        XCTAssertEqual(f.wagons[0].wagonClass, 2)
        XCTAssertEqual(f.wagons[0].features, ["wheelchair"])
        XCTAssertEqual(f.wagons[1].wagonClass, 1)
    }

    func testFormationWithoutWagonsIsNil() {
        XCTAssertNil(Formation.from(json: ["track": "3"]))
    }

    func testTrackPayloadCarriesStationIdentity() {
        let station = Station(
            id: "8507000", name: "Bern", lat: 46.9489, lon: 7.4399,
            mode: .train, dist: nil, embeddedDepartures: nil
        )
        let data = PhoneWatchService.GarminPayload.track(TourMockData.focused(base: 0), station: station)
        XCTAssertEqual(data["action"] as? String, "track")
        XCTAssertEqual(data["stId"] as? String, "8507000")
        XCTAssertEqual(data["stName"] as? String, "Bern")
        XCTAssertEqual(data["stLat"] as? Double, 46.9489)
        XCTAssertEqual(data["stLon"] as? Double, 7.4399)
    }

    func testTrackPayloadWithoutStationOmitsStationKeys() {
        let data = PhoneWatchService.GarminPayload.track(TourMockData.focused(base: 0), station: nil)
        XCTAssertNil(data["stId"])
        XCTAssertNil(data["stName"])
    }

    func testSyncMinimumRequires05OrHigher() {
        XCTAssertTrue(WatchSyncProtocol.meetsSyncMinimum("0.5.0"))
        XCTAssertTrue(WatchSyncProtocol.meetsSyncMinimum("0.5.1"))
        XCTAssertTrue(WatchSyncProtocol.meetsSyncMinimum("0.5.x"))
        XCTAssertTrue(WatchSyncProtocol.meetsSyncMinimum("0.6.0"))
        XCTAssertTrue(WatchSyncProtocol.meetsSyncMinimum("1.0.0"))
        XCTAssertFalse(WatchSyncProtocol.meetsSyncMinimum("0.4.x"))
        XCTAssertFalse(WatchSyncProtocol.meetsSyncMinimum("0.4.9"))
        XCTAssertFalse(WatchSyncProtocol.meetsSyncMinimum(nil))
        XCTAssertFalse(WatchSyncProtocol.meetsSyncMinimum(""))
        XCTAssertFalse(WatchSyncProtocol.meetsSyncMinimum("garbage"))
    }

    func testTourModeStepFollowsNearbyWithPerModeBoards() {
        XCTAssertEqual(tourSteps[0].stage, .nearby)
        XCTAssertEqual(tourSteps[1].stage, .mode)
        let trainLines = TourMockData.departures(base: 0, mode: .train).map(\.lineNumber)
        let busLines = TourMockData.departures(base: 0, mode: .bus).map(\.lineNumber)
        let tramLines = TourMockData.departures(base: 0, mode: .tram).map(\.lineNumber)
        XCTAssertTrue(trainLines.contains(TourMockData.trackLine))
        XCTAssertTrue(trainLines.contains(TourMockData.favouriteLine))
        XCTAssertTrue(Set(trainLines).isDisjoint(with: busLines))
        XCTAssertTrue(Set(trainLines).isDisjoint(with: tramLines))
    }

    private var tourWithV2Step: [TourStep] {
        tourSteps + [TourStep(stage: .widget, title: "New thing", body: "Body", introducedIn: 2)]
    }

    func testNewInstallSeesEveryStep() {
        XCTAssertEqual(stepsToShow(tourWithV2Step, effectiveSeen: 0, current: 2).count, tourWithV2Step.count)
    }

    func testUpdaterSeesOnlyNewerSteps() {
        let shown = stepsToShow(tourWithV2Step, effectiveSeen: 1, current: 2)
        XCTAssertEqual(shown.map(\.stage), [.widget])
        XCTAssertEqual(shown.first?.introducedIn, 2)
    }

    func testUpToDateUserSeesNothing() {
        XCTAssertTrue(stepsToShow(tourWithV2Step, effectiveSeen: 2, current: 2).isEmpty)
    }

    func testEffectiveSeenVersionMigratesLegacyFinisher() {
        XCTAssertEqual(effectiveSeenVersion(hasSeen: true, seenVersion: 0), 1)
        XCTAssertEqual(effectiveSeenVersion(hasSeen: false, seenVersion: 0), 0)
        XCTAssertEqual(effectiveSeenVersion(hasSeen: true, seenVersion: 3), 3)
    }
}
