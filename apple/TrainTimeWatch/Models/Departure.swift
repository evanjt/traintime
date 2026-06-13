import Foundation

struct Departure: Identifiable {
    let id = UUID()
    let destination: String
    let minutesUntil: Int
    let departureTimestamp: Int?
    let delay: Int
    let platform: String
    let platformChanged: Bool
    let lineNumber: String
    let category: String
    let trainNumber: String?
    let operatorRef: String?

    /// Parse a single departure entry from the API JSON
    static func from(json: [String: Any]) -> Departure {
        let destination = json["to"] as? String ?? "?"
        let category = json["category"] as? String ?? ""
        let number = json["number"] as? String ?? ""
        let lineNumber = number
        let trainNumber = json["trainNumber"] as? String
        let operatorRef = json["operatorRef"] as? String

        let platform = json["platform"] as? String ?? ""
        let platformChanged = json["platformChanged"] as? Bool ?? false

        var minutesUntil = -1
        var depTimestamp: Int?
        let now = Int(Date().timeIntervalSince1970)
        if let depTs = json["departure"] as? Int {
            depTimestamp = depTs
            minutesUntil = (depTs - now) / 60
        }

        var delay = 0
        if let rawDelay = json["delay"] as? Int, rawDelay > 0 {
            delay = rawDelay
        }

        return Departure(
            destination: destination,
            minutesUntil: minutesUntil,
            departureTimestamp: depTimestamp,
            delay: delay,
            platform: platform,
            platformChanged: platformChanged,
            lineNumber: lineNumber,
            category: category,
            trainNumber: trainNumber,
            operatorRef: operatorRef
        )
    }

    var isGone: Bool { minutesUntil < 0 }

    /// Identity stable across fetches (unlike `id`, a fresh UUID each parse). The triple
    /// matches how `FavouritesStore.merging` dedupes, so it is unique within one list.
    var stableId: String { "\(departureTimestamp ?? 0)|\(lineNumber)|\(destination)" }

    /// Seconds until departure (more precise than minutesUntil for tracking)
    var secondsUntil: Int? {
        guard let ts = departureTimestamp else { return nil }
        return ts - Int(Date().timeIntervalSince1970)
    }

    var minutesText: String {
        if isGone { return "gone" }
        if minutesUntil == 0 { return "now" }
        return "\(minutesUntil)'"
    }
}
