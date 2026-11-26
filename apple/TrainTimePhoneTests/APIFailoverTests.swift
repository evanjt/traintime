import XCTest
@testable import TrainTimePhone

final class APIFailoverTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPolicyTable() {
        for status in [200, 400, 401, 404] {
            XCTAssertFalse(FailoverPolicy.shouldFailover(status: status), "\(status)")
        }
        for status in [429, 500, 502, 503] {
            XCTAssertTrue(FailoverPolicy.shouldFailover(status: status), "\(status)")
        }
    }

    func testUpstreamUnavailableEndsFailover() {
        let upstream = Data(#"{"error":"upstream_unavailable"}"#.utf8)
        XCTAssertFalse(FailoverPolicy.shouldFailover(status: 503, body: upstream))
        XCTAssertFalse(FailoverPolicy.shouldFailover(status: 504, body: upstream))
        XCTAssertTrue(FailoverPolicy.shouldFailover(status: 503, body: nil))
        XCTAssertTrue(FailoverPolicy.shouldFailover(status: 503, body: Data("<html>Service Unavailable</html>".utf8)))
        XCTAssertTrue(FailoverPolicy.shouldFailover(status: 500, body: Data(#"{"error":"Internal error"}"#.utf8)))
    }

    func testUpstreamUnavailableIsReadFromTheErrorField() {
        XCTAssertTrue(FailoverPolicy.isUpstreamUnavailable(Data(#"{"error": "upstream_unavailable"}"#.utf8)))
        XCTAssertFalse(FailoverPolicy.isUpstreamUnavailable(Data(#"{"message":"upstream_unavailable"}"#.utf8)))
        XCTAssertFalse(FailoverPolicy.isUpstreamUnavailable(Data(#"{"error":"OJP API error: 502"}"#.utf8)))
        XCTAssertFalse(FailoverPolicy.isUpstreamUnavailable(Data("not json".utf8)))
        XCTAssertFalse(FailoverPolicy.isUpstreamUnavailable(Data()))
        XCTAssertFalse(FailoverPolicy.isUpstreamUnavailable(nil))
    }

    func testCancellationNeverFailsOver() {
        XCTAssertFalse(FailoverPolicy.shouldFailover(error: CancellationError()))
        XCTAssertFalse(FailoverPolicy.shouldFailover(error: URLError(.cancelled)))
        XCTAssertTrue(FailoverPolicy.shouldFailover(error: URLError(.timedOut)))
        XCTAssertTrue(FailoverPolicy.shouldFailover(error: URLError(.cannotConnectToHost)))
    }

    func testAttemptTimeoutsFitInsideRequestTimeout() {
        let n = ApiHost.all.count
        XCTAssertEqual(FailoverPolicy.attemptTimeout(attempt: 0, hostCount: n), Timing.firstAttemptTimeout)
        XCTAssertEqual(FailoverPolicy.attemptTimeout(attempt: n - 1, hostCount: n), Timing.lastAttemptTimeout)
        XCTAssertEqual(FailoverPolicy.attemptTimeout(attempt: 0, hostCount: 1), Timing.lastAttemptTimeout)
        let total = (0..<n).map { FailoverPolicy.attemptTimeout(attempt: $0, hostCount: n) }.reduce(0, +)
        XCTAssertLessThan(total, Timing.requestTimeout)
    }

    func testDefaultOrderIsPrimaryFirst() {
        XCTAssertEqual(HostState(hostCount: 3).order(now: t0), [0, 1, 2])
        XCTAssertEqual(ApiHost.all.first, ApiHost.defaultURL)
    }

    func testStickyAfterFailureAndSuccessOnSecondary() {
        var state = HostState(hostCount: 3)
        state.recordFailure(0, now: t0)
        state.recordSuccess(1)
        XCTAssertEqual(state.order(now: t0 + 1), [1, 0, 2])
        state.recordSuccess(2)
        XCTAssertEqual(state.order(now: t0 + 1), [2, 0, 1])
    }

    func testPrimaryIsReprobedAfterInterval() {
        var state = HostState(hostCount: 3)
        state.recordFailure(0, now: t0)
        state.recordSuccess(1)
        XCTAssertEqual(state.order(now: t0 + 299), [1, 0, 2])
        XCTAssertEqual(state.order(now: t0 + 301), [0, 1, 2])
    }

    func testPrimarySuccessClearsTheFailure() {
        var state = HostState(hostCount: 3)
        state.recordFailure(0, now: t0)
        state.recordSuccess(1)
        state.recordSuccess(0)
        XCTAssertEqual(state.order(now: t0 + 1), [0, 1, 2])
        XCTAssertNil(state.primaryFailedAt)
    }

    func testFailedReprobeStaysOnSecondary() {
        var state = HostState(hostCount: 3)
        state.recordFailure(0, now: t0)
        state.recordSuccess(1)
        state.recordFailure(0, now: t0 + 301)
        state.recordSuccess(1)
        XCTAssertEqual(state.order(now: t0 + 302), [1, 0, 2])
    }
}
