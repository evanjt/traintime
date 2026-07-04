import Foundation
import CoreLocation

struct Station: Identifiable {
    let id: String?
    let name: String?
    let lat: Double?
    let lon: Double?
    let mode: TransportMode
    var dist: Double?
    var embeddedDepartures: [Departure]?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Parse a station entry from the worker API grouped response
    static func from(json: [String: Any], mode: TransportMode) -> Station? {
        let id = json["id"] as? String
        guard id != nil else { return nil }

        let name = json["name"] as? String
        let lat = json["lat"] as? Double
        let lon = json["lon"] as? Double
        let dist = json["dist"] as? Double

        var embeddedDeps: [Departure]?
        if let depsArray = json["departures"] as? [[String: Any]], !depsArray.isEmpty {
            embeddedDeps = depsArray.prefix(Thresholds.maxDepartures).map { Departure.from(json: $0) }.dedupedForDisplay()
        }

        return Station(id: id, name: name, lat: lat, lon: lon, mode: mode, dist: dist, embeddedDepartures: embeddedDeps)
    }

    func walkInfo(index: Int, total: Int) -> String {
        let d = dist ?? 0
        let base = GeoUtils.formatWalkInfo(distanceMeters: d)
        if total > 1 {
            return "\(base)  \(index + 1)/\(total)"
        }
        return base
    }
}
