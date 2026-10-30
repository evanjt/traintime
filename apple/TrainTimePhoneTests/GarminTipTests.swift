import XCTest
@testable import TrainTimePhone

// Mirrors the Android GarminTipTest so the tip behaves identically on both phones.
final class GarminTipTests: XCTestCase {
    private func show(
        garminConnectInstalled: Bool = true,
        everLinked: Bool = false,
        seen: Bool = false,
        tourDone: Bool = true,
        launches: Int = GarminTipGate.minLaunches
    ) -> Bool {
        GarminTipGate.shouldShow(
            garminConnectInstalled: garminConnectInstalled, everLinked: everLinked, seen: seen, tourDone: tourDone,
            launches: launches)
    }

    func testGarminConnectOnThePhoneAndNeverLinkedShowsTheTip() {
        XCTAssertTrue(show())
    }

    func testNoGarminConnectNeverShows() {
        XCTAssertFalse(show(garminConnectInstalled: false))
    }

    func testAGarminThatHasEverLinkedNeverShows() {
        XCTAssertFalse(show(everLinked: true))
    }

    func testSeenOnceNeverShowsAgain() {
        XCTAssertFalse(show(seen: true))
    }

    func testWaitsUntilTheOnboardingTourIsDone() {
        XCTAssertFalse(show(tourDone: false))
    }

    func testWaitsForAFewLaunches() {
        XCTAssertFalse(show(launches: GarminTipGate.minLaunches - 1))
    }

    func testStoreURLFollowsTheAppLanguage() {
        let id = ConnectIqStore.appID
        XCTAssertEqual(ConnectIqStore.url(language: "de").absoluteString, "https://apps.garmin.com/de-DE/apps/\(id)")
        XCTAssertEqual(ConnectIqStore.url(language: "fr-CH").absoluteString, "https://apps.garmin.com/fr-FR/apps/\(id)")
        XCTAssertEqual(ConnectIqStore.url(language: "it").absoluteString, "https://apps.garmin.com/it-IT/apps/\(id)")
        XCTAssertEqual(ConnectIqStore.url(language: "en").absoluteString, "https://apps.garmin.com/en-US/apps/\(id)")
        XCTAssertEqual(ConnectIqStore.url(language: "rm").absoluteString, "https://apps.garmin.com/en-US/apps/\(id)")
    }
}
