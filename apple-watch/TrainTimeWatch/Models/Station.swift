import Foundation
import CoreLocation

struct Station: Identifiable {
    let id: String?
    let name: String?
    let lat: Double?
    let lon: Double?
    let icon: String?
    var dist: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var mode: TransportMode {
        TransportMode.from(icon: icon)
    }

    /// Parse a station entry from transport.opendata.ch locations response
    static func from(json: [String: Any], userCoord: CLLocationCoordinate2D?) -> Station? {
        let id = json["id"] as? String
        guard id != nil else { return nil }

        let name = json["name"] as? String
        let icon = json["icon"] as? String

        var lat: Double?
        var lon: Double?
        if let coordinate = json["coordinate"] as? [String: Any] {
            // API uses x=lat, y=lon
            lat = coordinate["x"] as? Double
            lon = coordinate["y"] as? Double
        }

        var dist: Double?
        // Use distance from API if available
        if let apiDist = json["distance"] as? Double {
            dist = apiDist
        } else if let userCoord = userCoord, let lat = lat, let lon = lon {
            dist = GeoUtils.haversineDistance(
                from: userCoord,
                to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }

        return Station(id: id, name: name, lat: lat, lon: lon, icon: icon, dist: dist)
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
