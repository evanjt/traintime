import Foundation

struct FormationWagon {
    let position: Int
    let number: Int
    let wagonClass: Int // 1 or 2
    let sector: String
    let features: [String] // "wheelchair", "restaurant", "family", "business", "low_floor"
    let closed: Bool
}

struct Formation {
    let track: String
    let sectors: [String]
    let wagons: [FormationWagon]

    static let railCategories: Set<String> = [
        "IR", "IC", "EC", "ICE", "TGV", "RJX", "RE", "R", "S", "PE", "EXT", "NJ", "EN"
    ]

    static func isRailCategory(_ category: String) -> Bool {
        railCategories.contains(category)
    }

    static func from(json: [String: Any]) -> Formation? {
        let track = json["track"] as? String ?? ""
        let sectors = json["sectors"] as? [String] ?? []
        guard let wagonArray = json["wagons"] as? [[String: Any]] else { return nil }

        let wagons = wagonArray.compactMap { w -> FormationWagon? in
            guard let position = w["position"] as? Int,
                  let number = w["number"] as? Int,
                  let wagonClass = w["class"] as? Int else { return nil }
            let sector = w["sector"] as? String ?? ""
            let features = w["features"] as? [String] ?? []
            let closed = w["closed"] as? Bool ?? false
            return FormationWagon(
                position: position,
                number: number,
                wagonClass: wagonClass,
                sector: sector,
                features: features,
                closed: closed
            )
        }

        guard !wagons.isEmpty else { return nil }
        return Formation(track: track, sectors: sectors, wagons: wagons)
    }
}
