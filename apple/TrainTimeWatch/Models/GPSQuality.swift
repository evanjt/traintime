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
