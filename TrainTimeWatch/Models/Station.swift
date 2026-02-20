import Foundation

struct Station: Decodable, Identifiable {
    let id: String?
    let label: String?
    let dist: Int?

    var walkInfo: String {
        let dist = dist ?? 0
        let walkMinutes = dist / 83
        let timeStr = walkMinutes < 1 ? "<1 min" : "\(walkMinutes) min"
        return "\(timeStr) walk - \(dist)m"
    }

    func walkInfoWithCounter(index: Int, total: Int) -> String {
        if total > 1 {
            return "\(walkInfo)  \(index + 1)/\(total)"
        }
        return walkInfo
    }
}
