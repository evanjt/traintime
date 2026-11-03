import XCTest
import UserNotifications
@testable import TrainTimePhone

final class AlertSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "AlertSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSoundsOnByDefault() {
        XCTAssertEqual(AlertSound.choice(defaults), .standard)
    }

    func testSoundsOffPicksSilentFileNotNil() {
        defaults.set(false, forKey: AlertSound.key)
        XCTAssertEqual(AlertSound.choice(defaults), .silent)
        XCTAssertNotNil(AlertSound.notificationSound(.silent))
        XCTAssertNotEqual(AlertSound.notificationSound(.silent), UNNotificationSound.default)
        XCTAssertEqual(AlertSound.notificationSound(.standard), UNNotificationSound.default)
    }

    func testSilentFileShipsInAppBundle() {
        let parts = AlertSound.silentFile.split(separator: ".")
        XCTAssertNotNil(Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])))
    }

    func testHapticGateFollowsSetting() {
        XCTAssertTrue(PhoneHapticService.isEnabled(defaults))
        defaults.set(false, forKey: PhoneHapticService.key)
        XCTAssertFalse(PhoneHapticService.isEnabled(defaults))
        defaults.set(true, forKey: PhoneHapticService.key)
        XCTAssertTrue(PhoneHapticService.isEnabled(defaults))
    }

    func testPlatformChangeAlertsWhenUnset() {
        XCTAssertTrue(PlatformChangeAlert.fires(switched: true, defaults))
    }

    func testPlatformChangeAlertSilencedWhenOff() {
        defaults.set(false, forKey: PlatformChangeAlert.key)
        XCTAssertFalse(PlatformChangeAlert.fires(switched: true, defaults))
        defaults.set(true, forKey: PlatformChangeAlert.key)
        XCTAssertTrue(PlatformChangeAlert.fires(switched: true, defaults))
    }

    func testNoPlatformChangeAlertWithoutASwitch() {
        XCTAssertFalse(PlatformChangeAlert.fires(switched: false, defaults))
    }
}

final class TripMuteTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "TripMuteTests"
    private let dep = 1_800_000_000

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFollowsSettingsWithoutATripChoice() {
        XCTAssertEqual(TripMute.look(global: true, session: nil), .on)
        XCTAssertEqual(TripMute.look(global: false, session: nil), .off)
    }

    func testATripMuteOverridesSettingsOn() {
        XCTAssertFalse(TripMute.effective(global: true, session: false))
        XCTAssertEqual(TripMute.look(global: true, session: false), .thisTrip)
    }

    func testATripUnmuteOverridesSettingsOff() {
        XCTAssertTrue(TripMute.effective(global: false, session: true))
        XCTAssertEqual(TripMute.look(global: false, session: true), .on)
    }

    func testTapFlipsThisTripAndLandsBackOnSettings() {
        XCTAssertEqual(TripMute.tapped(global: true, session: nil), false)
        XCTAssertNil(TripMute.tapped(global: true, session: false))
        XCTAssertEqual(TripMute.tapped(global: false, session: nil), true)
        XCTAssertNil(TripMute.tapped(global: false, session: true))
    }

    func testHoldTurnsItOffForEveryTripUnlessSettingsAlreadyShowsOff() {
        let rows: [(global: Bool, session: Bool?, settings: Bool)] = [
            (true, nil, false),
            (true, false, false),
            (false, true, false),
            (false, nil, true),
        ]
        for row in rows {
            let hold = TripMute.held(global: row.global, session: row.session)
            XCTAssertEqual(hold.global, row.settings, "global \(row.global) session \(String(describing: row.session))")
            XCTAssertNil(hold.session, "global \(row.global) session \(String(describing: row.session))")
        }
    }

    func testATripMuteSilencesAlertsWithSoundsOn() {
        XCTAssertEqual(AlertSound.choice(defaults, session: false), .silent)
        XCTAssertNotEqual(AlertSound.notificationSound(AlertSound.choice(defaults, session: false)), UNNotificationSound.default)
    }

    func testATripUnmuteSoundsAlertsWithSoundsOff() {
        defaults.set(false, forKey: AlertSound.key)
        XCTAssertEqual(AlertSound.choice(defaults, session: true), .standard)
        XCTAssertEqual(AlertSound.notificationSound(AlertSound.choice(defaults, session: true)), UNNotificationSound.default)
    }

    func testATripBuzzChoiceOverridesTheHapticSetting() {
        XCTAssertFalse(PhoneHapticService.isEnabled(defaults, session: false))
        defaults.set(false, forKey: PhoneHapticService.key)
        XCTAssertTrue(PhoneHapticService.isEnabled(defaults, session: true))
        XCTAssertFalse(PhoneHapticService.isEnabled(defaults, session: nil))
    }

    // The second caption states the Settings value, which the look alone can't
    // carry: on for this trip reads the same whether Settings is on or off.
    func testOffInSettingsReadsUsuallyOff() {
        let state = TripMute.state(global: false, session: nil)
        XCTAssertEqual(state.look, .off)
        XCTAssertEqual(TripMute.usualCaption(state), "Usually off")
    }

    func testMutedForThisTripReadsUsuallyOn() {
        let state = TripMute.state(global: true, session: false)
        XCTAssertEqual(state.look, .thisTrip)
        XCTAssertEqual(TripMute.usualCaption(state), "Usually on")
    }

    func testOnFollowsSettings() {
        XCTAssertEqual(TripMute.usualCaption(TripMute.state(global: true, session: nil)), "Usually on")
    }

    func testOnForThisTripOverSettingsOffReadsUsuallyOff() {
        let state = TripMute.state(global: false, session: true)
        XCTAssertEqual(state.look, .on)
        XCTAssertEqual(TripMute.usualCaption(state), "Usually off")
    }

    // On for this trip only shows over Settings off, and a hold from there
    // keeps it off, so its tap hint must not promise a hold turns it on.
    func testOnForThisTripHintNeverNamesTheHold() {
        XCTAssertEqual(TripMute.tripHint(true), "On for this trip.")
    }

    func testMutedForThisTripHintStillNamesTheHold() {
        XCTAssertEqual(TripMute.tripHint(false), "Muted for this trip. Hold to mute always.")
        XCTAssertNil(TripMute.tripHint(nil))
    }

    func testMutesOnlyApplyToTheirOwnDeparture() {
        var mutes = TripMutes()
        mutes.set(\.sound, false, for: dep)
        XCTAssertEqual(mutes.scoped(to: dep).sound, false)
        XCTAssertNil(mutes.scoped(to: dep + 600).sound)
        XCTAssertNil(mutes.scoped(to: nil).sound)
    }

    func testANewDepartureStartsWithNoMutes() {
        var mutes = TripMutes()
        mutes.set(\.buzz, false, for: dep)
        mutes.set(\.sound, false, for: dep + 600)
        XCTAssertNil(mutes.scoped(to: dep + 600).buzz)
        XCTAssertEqual(mutes.scoped(to: dep + 600).sound, false)
    }
}
