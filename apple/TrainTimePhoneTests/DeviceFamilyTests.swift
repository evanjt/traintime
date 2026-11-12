import XCTest

// Reads the built Info.plists, so the test checks what the store receives.
final class DeviceFamilyTests: XCTestCase {
    private let iPadOrientations: Set<String> = [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ]

    // Reads the file, since infoDictionary folds `~ipad` keys into the base key per device.
    private func info(_ bundle: Bundle?, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
        guard let url = bundle?.bundleURL.appendingPathComponent("Info.plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            XCTFail("Info.plist not found", file: file, line: line)
            return [:]
        }
        return dict
    }

    private func plugIn(_ name: String) -> Bundle? {
        guard let dir = Bundle.main.builtInPlugInsURL else { return nil }
        return Bundle(url: dir.appendingPathComponent("\(name).appex"))
    }

    func testTheAppAndItsExtensionsRunOnIPhoneAndIPad() {
        for (name, bundle) in [
            ("app", Bundle.main),
            ("widget", plugIn("TrainTimeWidgetExtension")),
            ("share", plugIn("TrainTimeShareExtension")),
        ] {
            let family = info(bundle)["UIDeviceFamily"] as? [Int] ?? []
            XCTAssertEqual(Set(family), [1, 2], name)
        }
    }

    func testTheAppDeclaresEveryIPadOrientationForMultitasking() {
        let main = info(Bundle.main)
        let list = main["UISupportedInterfaceOrientations~ipad"] as? [String] ?? []
        XCTAssertEqual(Set(list), iPadOrientations)
        XCTAssertNotEqual(main["UIRequiresFullScreen"] as? Bool, true)
    }

    func testTheIPhoneOrientationsStayAsTheyWere() {
        XCTAssertNil(info(Bundle.main)["UISupportedInterfaceOrientations"])
    }
}
