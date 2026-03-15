import SwiftUI

enum TransportMode: Int, CaseIterable, Identifiable {
    case train = 0
    case bus = 1
    case tram = 2
    case special = 3

    var id: Int { rawValue }

    var sfSymbol: String {
        switch self {
        case .train: return "train.side.front.car"
        case .bus: return "bus.fill"
        case .tram: return "tram.fill"
        case .special: return "ferry.fill"
        }
    }

    var label: String {
        switch self {
        case .train: return "Train"
        case .bus: return "Bus"
        case .tram: return "Tram"
        case .special: return "Special"
        }
    }

    /// Categorize a station icon string from the API into a transport mode.
    /// null/unknown icons are treated as train (S-Bahn, IC, IR, RE).
    static func from(icon: String?) -> TransportMode {
        switch icon {
        case "bus": return .bus
        case "tram": return .tram
        case "special": return .special
        default: return .train
        }
    }
}
