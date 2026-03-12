import Foundation
import CoreLocation

enum GeoUtils {
    /// Approximate distance in meters using flat-earth approximation (matches Garmin implementation)
    static func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLat = (to.latitude - from.latitude) * 111000.0
        let dLon = (to.longitude - from.longitude) * 75700.0
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    /// Bearing in radians from one coordinate to another (great-circle, matches Garmin's calculateBearing)
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLon = (to.longitude - from.longitude) * .pi / 180.0
        let lat1R = from.latitude * .pi / 180.0
        let lat2R = to.latitude * .pi / 180.0
        let y = sin(dLon) * cos(lat2R)
        let x = cos(lat1R) * sin(lat2R) - sin(lat1R) * cos(lat2R) * cos(dLon)
        return atan2(y, x)
    }

    /// Walk time in minutes at 83 m/min (matches Garmin's walkSpeed)
    static func walkMinutes(distanceMeters: Double) -> Double {
        distanceMeters / 83.0
    }

    /// Format walk info string matching Garmin's display
    /// When walkTimeSeconds is provided (from MKDirections), uses that instead of the 83 m/min estimate
    static func formatWalkInfo(distanceMeters: Double, walkTimeSeconds: Double? = nil) -> String {
        let walkMin: Int
        if let walkTime = walkTimeSeconds {
            walkMin = Int(walkTime / 60.0)
        } else {
            walkMin = Int(walkMinutes(distanceMeters: distanceMeters))
        }
        let timeStr = walkMin < 1 ? "<1 min" : "\(walkMin) min"
        return "\(timeStr) walk - \(Int(distanceMeters))m"
    }
}
