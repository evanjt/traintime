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
