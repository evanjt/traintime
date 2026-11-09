import SwiftUI

enum GPSQuality {
    case unavailable
    case lastKnown
    case poor
    case good

    var color: Color {
        switch self {
        case .unavailable: return .red
        case .lastKnown: return .gray
        case .poor: return .orange
        case .good: return .green
        }
    }

    static func from(accuracy: Double?) -> GPSQuality {
        guard let accuracy = accuracy else { return .unavailable }
        if accuracy < 0 { return .unavailable }
        if accuracy > 100 { return .poor }
        if accuracy > 30 { return .poor }
        return .good
    }
}

enum LocationFix {
    /// Core Location replays its cached fix first when updates start, so a fix older
    /// than this is a remembered position, not proof of where the device is now.
    static let liveMaxAge: TimeInterval = 5

    enum Verdict: Equatable { case live, cached, ignore }

    /// A replayed fix only stands in when nothing is held yet. It must never replace
    /// a held coordinate, which is at least as recent.
    static func verdict(age: TimeInterval, horizontalAccuracy: Double, holdingCoordinate: Bool) -> Verdict {
        if horizontalAccuracy < 0 { return .ignore }
        if age <= liveMaxAge { return .live }
        return holdingCoordinate ? .ignore : .cached
    }

    enum CachedBoard: Equatable { case keep, waitForRequest, refetch }

    /// What a board fetched from a cached position does once a live fix lands. Within the
    /// movement threshold it is the same board, so it is kept without another request.
    static func cachedBoardOnLiveFix(requestInFlight: Bool, movedFromSearch: Bool?) -> CachedBoard {
        if requestInFlight { return .waitForRequest }
        if movedFromSearch == false { return .keep }
        return .refetch
    }
}
