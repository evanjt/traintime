import Foundation
import CoreLocation

enum GeoUtils {
    /// Approximate distance in meters using flat-earth approximation (matches Garmin implementation)
    static func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLat = (to.latitude - from.latitude) * 111000.0
        let dLon = (to.longitude - from.longitude) * 75700.0
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    /// Bearing in radians from one coordinate to another (matches Garmin's calculateBearing)
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLat = (to.latitude - from.latitude) * 111000.0
        let dLon = (to.longitude - from.longitude) * 75700.0
        return atan2(dLon, dLat)
    }

    /// Walk time in minutes at 83 m/min (matches Garmin's walkSpeed)
    static func walkMinutes(distanceMeters: Double) -> Double {
        distanceMeters / 83.0
    }

    /// Format walk info string matching Garmin's display
    static func formatWalkInfo(distanceMeters: Double) -> String {
        let walkMin = Int(walkMinutes(distanceMeters: distanceMeters))
        let timeStr = walkMin < 1 ? "<1 min" : "\(walkMin) min"
        return "\(timeStr) walk - \(Int(distanceMeters))m"
    }
}
