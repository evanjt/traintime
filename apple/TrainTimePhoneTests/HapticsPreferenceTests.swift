import XCTest
@testable import TrainTimePhone

final class HapticsPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "HapticsPreferenceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testUnsetKeyAllowsHaptics() {
        XCTAssertTrue(HapticsPreference.isEnabled(in: defaults))
    }

    func testFalseKeyBlocksHaptics() {
        defaults.set(false, forKey: HapticsPreference.key)
        XCTAssertFalse(HapticsPreference.isEnabled(in: defaults))
    }

    func testTrueKeyAllowsHaptics() {
        defaults.set(true, forKey: HapticsPreference.key)
        XCTAssertTrue(HapticsPreference.isEnabled(in: defaults))
    }
}
