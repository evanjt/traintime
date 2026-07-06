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

    /// Identity stable across fetches (unlike `id`, a fresh UUID each parse). Includes
    /// trainNumber because OJP can list distinct journeys in the same minute; excludes
    /// platform, which mutates across fetches (platformChanged) and would churn identity.
    var stableId: String { "\(departureTimestamp ?? 0)|\(lineNumber)|\(destination)|\(trainNumber ?? "")" }

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

extension Array where Element == Departure {
    /// OJP can publish the same physical train twice under different journey numbers
    /// (seen live: Léman Express RL4 → Coppet as 23153 and 93153, only one carrying
    /// the real-time delay). Collapse rows a passenger can't tell apart, keeping the
    /// delay-bearing one. The key deliberately excludes trainNumber. It is the field
    /// that differs on such twins.
    func dedupedForDisplay() -> [Departure] {
        guard count > 1 else { return self }
        var result: [Departure] = []
        var indexByKey: [String: Int] = [:]
        for dep in self {
            let key = "\(dep.departureTimestamp ?? 0)|\(dep.lineNumber)|\(dep.destination)|\(dep.platform)"
            if let existing = indexByKey[key] {
                if dep.delay > result[existing].delay { result[existing] = dep }
            } else {
                indexByKey[key] = result.count
                result.append(dep)
            }
        }
        return result
    }
}
