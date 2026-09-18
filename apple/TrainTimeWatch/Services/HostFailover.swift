import Foundation

enum FailoverPolicy {
    /// A 429 or a 5xx is the host's problem, so the next host gets the request.
    /// 4xx below that is our own request and would fail the same way anywhere.
    static func shouldFailover(status: Int) -> Bool {
        status == 429 || status >= 500
    }

    /// A cancelled request is the caller's doing and never fails over.
    static func shouldFailover(error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        return true
    }

    /// Every host before the last gets the short budget, the last host the long one.
    static func attemptTimeout(attempt: Int, hostCount: Int) -> TimeInterval {
        attempt < hostCount - 1 ? Timing.firstAttemptTimeout : Timing.lastAttemptTimeout
    }
}

/// Which host to try first. Sticks to the host that last answered and re-probes
/// the primary once `reprobeInterval` has passed since it failed.
struct HostState {
    var hostCount: Int
    var reprobeInterval: TimeInterval = Timing.primaryReprobeInterval
    var activeIndex = 0
    var primaryFailedAt: Date?

    func order(now: Date) -> [Int] {
        let natural = Array(0..<hostCount)
        guard activeIndex != 0, let failedAt = primaryFailedAt,
              now.timeIntervalSince(failedAt) < reprobeInterval
        else { return natural }
        return [activeIndex] + natural.filter { $0 != activeIndex }
    }

    mutating func recordFailure(_ index: Int, now: Date) {
        if index == 0 { primaryFailedAt = now }
    }

    mutating func recordSuccess(_ index: Int) {
        activeIndex = index
        if index == 0 { primaryFailedAt = nil }
    }
}

actor HostFailover {
    static let shared = HostFailover()
    private var states: [Int: HostState] = [:]

    private func state(for hostCount: Int) -> HostState {
        states[hostCount] ?? HostState(hostCount: hostCount)
    }

    func order(hostCount: Int, now: Date = Date()) -> [Int] {
        state(for: hostCount).order(now: now)
    }

    func recordFailure(_ index: Int, hostCount: Int, now: Date = Date()) {
        var s = state(for: hostCount)
        s.recordFailure(index, now: now)
        states[hostCount] = s
    }

    func recordSuccess(_ index: Int, hostCount: Int) {
        var s = state(for: hostCount)
        s.recordSuccess(index)
        states[hostCount] = s
    }
}
