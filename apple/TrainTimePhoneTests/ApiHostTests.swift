import XCTest
@testable import TrainTimePhone

final class ApiHostTests: XCTestCase {
    func testValidHttpsOriginIsKept() {
        XCTAssertEqual(ApiHost.normalise("https://api.example.ch"), "https://api.example.ch")
        XCTAssertEqual(ApiHost.normalise("https://10.0.0.5:8443"), "https://10.0.0.5:8443")
    }

    func testTrailingSlashAndWhitespaceAreStripped() {
        XCTAssertEqual(ApiHost.normalise("  https://api.example.ch/  "), "https://api.example.ch")
        XCTAssertEqual(ApiHost.normalise("https://api.example.ch//"), "https://api.example.ch")
    }

    func testBlankMeansDefault() {
        XCTAssertEqual(ApiHost.normalise(""), "")
        XCTAssertEqual(ApiHost.normalise("   "), "")
        XCTAssertEqual(ApiHost.normalise("/"), "")
    }

    func testHttpIsRejected() {
        XCTAssertNil(ApiHost.normalise("http://api.example.ch"))
        XCTAssertNil(ApiHost.normalise("api.example.ch"))
    }

    func testPathQueryAndFragmentAreRejected() {
        XCTAssertNil(ApiHost.normalise("https://api.example.ch/v1"))
        XCTAssertNil(ApiHost.normalise("https://api.example.ch?key=1"))
        XCTAssertNil(ApiHost.normalise("https://api.example.ch#x"))
        XCTAssertNil(ApiHost.normalise("https://"))
    }
}
