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
                ["position": 2, "number": 102, "class": 1, "sector": "B", "noPassageAfter": true, "mixedClass": true],
            ],
        ]
        let f = Formation.from(json: json)!
        XCTAssertEqual(f.track, "3")
        XCTAssertEqual(f.sectors, ["A", "B"])
        XCTAssertEqual(f.wagons.count, 2)
        XCTAssertEqual(f.wagons[0].wagonClass, 2)
        XCTAssertEqual(f.wagons[0].features, ["wheelchair"])
        XCTAssertEqual(f.wagons[1].wagonClass, 1)
        XCTAssertFalse(f.wagons[0].noPassageAfter)
        XCTAssertTrue(f.wagons[1].noPassageAfter)
        XCTAssertTrue(f.wagons[1].mixedClass)
    }

    func testFormationReadsNoPassageAndMixedClass() {
        let json: [String: Any] = [
            "track": "6", "sectors": ["A"],
            "wagons": [
                ["position": 1, "number": 11, "class": 1, "sector": "A", "noPassageAfter": true],
                ["position": 2, "number": 8, "class": 1, "sector": "A", "mixedClass": true],
            ],
        ]
        let f = Formation.from(json: json)!
        XCTAssertTrue(f.wagons[0].noPassageAfter)
        XCTAssertFalse(f.wagons[0].mixedClass)
        XCTAssertFalse(f.wagons[1].noPassageAfter)
        XCTAssertTrue(f.wagons[1].mixedClass)
    }

    func testFormationWithoutNewFlagsStillDecodes() {
        let json: [String: Any] = [
            "track": "3", "sectors": ["A"],
            "wagons": [["position": 1, "number": 5, "class": 2, "sector": "A", "features": ["kw"]]],
        ]
        let w = Formation.from(json: json)!.wagons[0]
        XCTAssertEqual(w.number, 5)
        XCTAssertFalse(w.noPassageAfter)
        XCTAssertFalse(w.mixedClass)
    }

    func testFormationCarTheFeedDoesNotNumberHasNoNumber() {
        let json: [String: Any] = [
            "track": "13", "sectors": ["A"],
            "wagons": [
                ["position": 1, "number": 1, "class": 2, "sector": "A", "numberUnknown": true],
                ["position": 2, "number": 12, "class": 2, "sector": "A"],
                ["position": 3, "number": 11, "class": 2, "sector": "A", "numberUnknown": false],
            ],
        ]
        XCTAssertEqual(Formation.from(json: json)!.wagons.map(\.number), [nil, 12, 11])
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

    func testGarminPingGateRequiresRecentAliveAfterByeOnPv2() {
        let now = Date(timeIntervalSince1970: 1_718_000_000)
        let bye = now.addingTimeInterval(-60)
        XCTAssertTrue(WatchSyncProtocol.shouldPingGarmin(
            lastAlive: now.addingTimeInterval(-5), lastBye: bye, now: now, pv: 2))
        // Old protocol never pinged
        XCTAssertFalse(WatchSyncProtocol.shouldPingGarmin(
            lastAlive: now.addingTimeInterval(-5), lastBye: bye, now: now, pv: 1))
        // Bye after alive: the watch app closed
        XCTAssertFalse(WatchSyncProtocol.shouldPingGarmin(
            lastAlive: now.addingTimeInterval(-10), lastBye: now.addingTimeInterval(-5), now: now, pv: 2))
        // Stale alive: outside the window
        XCTAssertFalse(WatchSyncProtocol.shouldPingGarmin(
            lastAlive: now.addingTimeInterval(-31), lastBye: bye, now: now, pv: 2))
        // Never heard from
        XCTAssertFalse(WatchSyncProtocol.shouldPingGarmin(
            lastAlive: .distantPast, lastBye: .distantPast, now: now, pv: 2))
    }

    func testGarminAckAndPingPayloadShapes() {
        let ack = PhoneWatchService.GarminPayload.ackReminder(id: "8507000|1718000600|IC1")
        XCTAssertEqual(ack["action"] as? String, "ackReminder")
        XCTAssertEqual(ack["id"] as? String, "8507000|1718000600|IC1")
        let ping = PhoneWatchService.GarminPayload.ping()
        XCTAssertEqual(ping["action"] as? String, "ping")
        XCTAssertEqual(ping.count, 1)
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

    // Synthetic step one version past the real tour, so it is always the sole
    // newest step regardless of what currentTourVersion introduces.
    private var nextVersion: Int { currentTourVersion + 1 }
    private var tourWithFutureStep: [TourStep] {
        tourSteps + [TourStep(stage: .widget, title: "New thing", body: "Body", introducedIn: nextVersion)]
    }

    func testNewInstallSeesEveryStep() {
        let shown = stepsToShow(tourWithFutureStep, effectiveSeen: 0, current: nextVersion)
        XCTAssertEqual(shown.count, tourWithFutureStep.count)
    }

    func testUpdaterSeesOnlyNewerSteps() {
        let shown = stepsToShow(tourWithFutureStep, effectiveSeen: currentTourVersion, current: nextVersion)
        XCTAssertEqual(shown.map(\.stage), [.widget])
        XCTAssertEqual(shown.first?.introducedIn, nextVersion)
    }

    func testUpToDateUserSeesNothing() {
        XCTAssertTrue(stepsToShow(tourWithFutureStep, effectiveSeen: nextVersion, current: nextVersion).isEmpty)
    }

    // v2 added the background disclosure and v3 the tracking row's Sound and
    // Buzz, so a v1 finisher catches up on both and a v2 finisher on the row only.
    func testV1FinisherSeesTheBackgroundAndMuteSteps() {
        let shown = stepsToShow(tourSteps, effectiveSeen: 1, current: currentTourVersion)
        XCTAssertEqual(shown.map(\.stage), [.background, .mute])
    }

    func testV2FinisherSeesOnlyTheMuteStep() {
        let shown = stepsToShow(tourSteps, effectiveSeen: 2, current: currentTourVersion)
        XCTAssertEqual(shown.map(\.stage), [.mute])
    }

    func testNewInstallSeesTheMuteStepRightAfterBackground() {
        let shown = stepsToShow(tourSteps, effectiveSeen: 0, current: currentTourVersion).map(\.stage)
        XCTAssertEqual(shown, tourSteps.map(\.stage))
        XCTAssertEqual(shown.firstIndex(of: .mute), shown.firstIndex(of: .background).map { $0 + 1 })
    }

    func testEffectiveSeenVersionMigratesLegacyFinisher() {
        XCTAssertEqual(effectiveSeenVersion(hasSeen: true, seenVersion: 0), 1)
        XCTAssertEqual(effectiveSeenVersion(hasSeen: false, seenVersion: 0), 0)
        XCTAssertEqual(effectiveSeenVersion(hasSeen: true, seenVersion: 3), 3)
    }

    // MARK: - Favourites union (outer-join sync)

    private func fav(_ station: String, _ line: String, _ dest: String, name: String? = nil) -> Favourite {
        Favourite(stationId: station, stationName: name ?? station, lineNumber: line, destination: dest)
    }

    func testFavouritesUnionKeepsEveryDistinctFavourite() {
        let local = [fav("8507000", "IC1", "Bern")]
        let remote = [fav("8501120", "IR90", "Visp")]
        XCTAssertEqual(FavouritesStore.union(local, remote).map(\.id), ["8507000:IC1:Bern", "8501120:IR90:Visp"])
    }

    func testFavouritesUnionDedupesOnIdDespiteNameDrift() {
        let local = [fav("8507000", "IC1", "Bern", name: "Bern")]
        let remote = [fav("8507000", "IC1", "Bern", name: "Bern Bahnhof")]
        let merged = FavouritesStore.union(local, remote)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.stationName, "Bern")
    }

    func testFavouritesUnionIsIdempotent() {
        let local = [fav("a", "1", "x"), fav("b", "2", "y")]
        let remote = [fav("b", "2", "y"), fav("c", "3", "z")]
        let once = FavouritesStore.union(local, remote)
        XCTAssertEqual(FavouritesStore.union(once, remote).map(\.id), once.map(\.id))
        XCTAssertEqual(once.map(\.id), ["a:1:x", "b:2:y", "c:3:z"])
    }

    // MARK: - Late departures

    // Scenario: a bus scheduled two minutes ago is running four minutes late.
    // Expected behaviour: it is not gone, keeps its delay, and reads "now" until
    // its effective time has passed.
    private func lateRow(minutesUntil: Int, delay: Int) -> Departure {
        Departure(destination: "Bern Bahnhof", minutesUntil: minutesUntil, departureTimestamp: nil, delay: delay,
                  platform: "", platformChanged: false, lineNumber: "10", category: "B",
                  trainNumber: nil, operatorRef: nil)
    }

    func testLateBusIsNotGoneUntilItsEffectiveTime() {
        XCTAssertFalse(lateRow(minutesUntil: -2, delay: 4).isGone)
        XCTAssertFalse(lateRow(minutesUntil: -4, delay: 4).isGone)
        XCTAssertTrue(lateRow(minutesUntil: -5, delay: 4).isGone)
        XCTAssertFalse(lateRow(minutesUntil: -15, delay: 20).isGone)
    }

    func testOnTimeBusKeepsGoneThreshold() {
        XCTAssertFalse(lateRow(minutesUntil: 0, delay: 0).isGone)
        XCTAssertTrue(lateRow(minutesUntil: -1, delay: 0).isGone)
    }

    func testLateBusReadsNowFromItsScheduledMinute() {
        XCTAssertEqual(lateRow(minutesUntil: 0, delay: 4).minutesText, "now")
        XCTAssertEqual(lateRow(minutesUntil: -2, delay: 4).minutesText, "now")
        XCTAssertEqual(lateRow(minutesUntil: -5, delay: 4).minutesText, "gone")
    }

    private func lateFocused(secondsFromNow: Int, delay: Int) -> FocusedDeparture {
        FocusedDeparture(destination: "Brig", departureTimestamp: Int(Date().timeIntervalSince1970) + secondsFromNow,
                         lineNumber: "IR90", category: "IR", trainNumber: nil, operatorRef: nil,
                         delay: delay, platform: "2", platformChanged: false)
    }

    func testCountdownDoesNotSayDepartedWhileTheLateTrainIsStillComing() {
        XCTAssertEqual(lateFocused(secondsFromNow: -60, delay: 4).countdownText, "now")
        XCTAssertEqual(lateFocused(secondsFromNow: -180, delay: 4).countdownText, "now")
        XCTAssertFalse(lateFocused(secondsFromNow: -180, delay: 4).effectiveMinutesUntil < -0.5)
    }

    func testCountdownSaysDepartedOnceTheEffectiveTimeHasPassed() {
        XCTAssertEqual(lateFocused(secondsFromNow: -60, delay: 0).countdownText, "Departed")
        XCTAssertEqual(lateFocused(secondsFromNow: -300, delay: 4).countdownText, "Departed")
    }

    // MARK: - One-leg route synthesis (save from board)

    private func brigDeparture(ts: Int = 1_750_000_000) -> Departure {
        Departure(destination: "Brig", minutesUntil: 42, departureTimestamp: ts, delay: 0,
                  platform: "3", platformChanged: false, lineNumber: "IR90", category: "IR",
                  trainNumber: "1820", operatorRef: nil)
    }

    private var bernStation: Station {
        Station(id: "8507000", name: "Bern", lat: 46.9489, lon: 7.4396, mode: .train,
                dist: nil, embeddedDepartures: nil)
    }

    func testSynthesisedLegCarriesOriginAndIsTrackable() {
        let route = SharedRoute.forDeparture(station: bernStation, departure: brigDeparture())
        let leg = route.legs[0]
        XCTAssertEqual(leg.originId, "8507000")
        XCTAssertEqual(leg.originLat, 46.9489)
        XCTAssertEqual(leg.destName, "Brig")
        XCTAssertEqual(leg.depTs, leg.arrTs)
        XCTAssertEqual(leg.lineNumber, "IR90")
        XCTAssertNil(leg.category)
        XCTAssertTrue(leg.isTrackable)
    }

    func testSynthesisedLegRoundTripsThroughMatchDeparture() {
        let dep = brigDeparture()
        let leg = SharedRoute.forDeparture(station: bernStation, departure: dep).legs[0]
        XCTAssertEqual(matchDeparture([dep], leg: leg)?.stableId, dep.stableId)
    }
}

// A 16-car double unit, front first, with no passage after the eleventh car and features as
// the API sends them, low floor and pram included.
enum FormationFixtures {
    static let doubleUnit: Formation = {
        let cars: [(Int, Int, String, [String])] = [
            (18, 2, "H", ["family", "low_floor"]), (17, 2, "H", ["low_floor", "bike"]),
            (16, 2, "G", ["low_floor", "bike"]), (15, 2, "G", ["wheelchair", "low_floor"]),
            (14, 2, "F", ["wheelchair", "low_floor"]), (13, 1, "F", ["low_floor", "bike"]),
            (12, 1, "E", ["low_floor", "bike"]), (11, 1, "E", ["business", "low_floor", "bike"]),
            (8, 2, "D", ["family", "low_floor"]), (7, 2, "D", ["low_floor", "bike"]),
            (6, 2, "C", ["low_floor", "bike"]), (5, 2, "B", ["wheelchair", "low_floor"]),
            (4, 2, "B", ["wheelchair", "restaurant", "low_floor"]), (3, 1, "B", ["low_floor", "bike"]),
            (2, 1, "A", ["low_floor", "bike"]), (1, 1, "A", ["business", "low_floor", "bike"]),
        ]
        let wagons = cars.enumerated().map { i, c in
            FormationWagon(position: i + 1, number: c.0, wagonClass: c.1, sector: c.2,
                           features: c.3, closed: false, noPassageAfter: c.0 == 11)
        }
        return Formation(track: "6", sectors: ["H", "G", "F", "E", "D", "C", "B", "A"], wagons: wagons)
    }()
}

final class FormationLayoutTests: XCTestCase {
    func testSixteenCarsFitAPhoneWidth() {
        let wagons = FormationFixtures.doubleUnit.wagons
        let layout = FormationLayout(wagons: wagons, width: 300)
        XCTAssertEqual(layout.carX.count, 16)
        XCTAssertLessThanOrEqual(layout.carX[15] + layout.carWidth, 300)
        XCTAssertGreaterThan(layout.carWidth, 12)
    }

    func testBreakWidensTheGapAndSplitsTheUnits() {
        let layout = FormationLayout(wagons: FormationFixtures.doubleUnit.wagons, width: 300)
        XCTAssertEqual(layout.units, [0..<8, 8..<16])
        XCTAssertEqual(layout.breaks.count, 1)
        let joined = layout.carX[7] - (layout.carX[6] + layout.carWidth)
        let broken = layout.carX[8] - (layout.carX[7] + layout.carWidth)
        XCTAssertGreaterThan(broken, joined)
        XCTAssertGreaterThan(layout.breaks[0], layout.carX[7] + layout.carWidth)
        XCTAssertLessThan(layout.breaks[0], layout.carX[8])
    }

    func testShortTrainKeepsTheWidestCar() {
        let wagons = Array(FormationFixtures.doubleUnit.wagons.prefix(3))
        let layout = FormationLayout(wagons: wagons, width: 340)
        XCTAssertEqual(layout.carWidth, FormationLayout.maxCarWidth)
    }

    func testNoPassageOnTheLastCarDrawsNoBreak() {
        let last = FormationWagon(position: 1, number: 1, wagonClass: 2, sector: "A", features: [],
                                  closed: false, noPassageAfter: true)
        let layout = FormationLayout(wagons: [last], width: 340)
        XCTAssertTrue(layout.breaks.isEmpty)
        XCTAssertEqual(layout.units, [0..<1])
    }

    func testLaneShowsOneFeatureByPriority() {
        func lane(_ features: [String], closed: Bool = false) -> String? {
            FormationLayout.laneFeature(FormationWagon(position: 1, number: 1, wagonClass: 2, sector: "A",
                                                       features: features, closed: closed))
        }
        XCTAssertEqual(lane(["wheelchair", "restaurant", "low_floor"]), "restaurant")
        XCTAssertEqual(lane(["business", "low_floor", "bike"]), "bike")
        XCTAssertEqual(lane(["family", "low_floor"]), "family")
        XCTAssertEqual(lane(["business"]), "business")
        XCTAssertNil(lane(["low_floor", "kw"]))
        XCTAssertNil(lane(["restaurant"], closed: true))
    }
}
