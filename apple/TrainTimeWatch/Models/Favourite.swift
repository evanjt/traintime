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
