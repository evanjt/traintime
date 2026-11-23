import XCTest
@testable import TrainTimePhone

// The attribution screens show Public Transport Victoria's credit as its CC BY 4.0 terms word it,
// in English in every app language, under a heading translated into each app language.
final class AttributionTests: XCTestCase {
    func testPTVCreditKeepsLicensorWording() {
        XCTAssertEqual(
            DataCredits.ptvLicence,
            "Source: Licensed from Public Transport Victoria under a Creative Commons Attribution 4.0 International Licence."
        )
        XCTAssertEqual(DataCredits.ccBy4URL, "https://creativecommons.org/licenses/by/4.0/")
    }

    func testVictoriaHeadingIsTranslatedInEachAppLanguage() throws {
        let expected = ["de": "Victoria, Australien", "fr": "Victoria, Australie", "it": "Victoria, Australia"]
        for (language, heading) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path), language)
            XCTAssertEqual(
                bundle.localizedString(forKey: "Victoria, Australia", value: "missing", table: nil),
                heading, language
            )
        }
    }
}
