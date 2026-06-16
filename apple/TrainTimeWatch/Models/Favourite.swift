import Foundation

struct Favourite: Codable, Equatable, Identifiable {
    let stationId: String
    let stationName: String
    let lineNumber: String
    let destination: String

    var id: String { "\(stationId):\(lineNumber):\(destination)" }

    /// Build display string: "IC8 → Brig @ Bern"
    var displayString: String {
        "\(lineNumber) → \(destination) @ \(stationName)"
    }
}

/// A pinned station ("My stations"). Stored with coordinates so proximity can be
/// computed offline. Defined here (rather than a new file) to ride the existing
/// all-targets membership of Favourite.swift.
struct PinnedStation: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let lat: Double?
    let lon: Double?
}
