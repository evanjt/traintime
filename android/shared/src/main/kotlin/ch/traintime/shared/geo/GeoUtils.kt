package ch.traintime.shared.geo

import ch.traintime.shared.Thresholds
import kotlin.math.*

object GeoUtils {
    fun haversineDistance(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double): Double {
        val dLat = (toLat - fromLat) * 111000.0
        val dLon = (toLon - fromLon) * 75700.0
        return sqrt(dLat * dLat + dLon * dLon)
    }

    fun bearing(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double): Double {
        val dLon = (toLon - fromLon) * PI / 180.0
        val lat1R = fromLat * PI / 180.0
        val lat2R = toLat * PI / 180.0
        val y = sin(dLon) * cos(lat2R)
        val x = cos(lat1R) * sin(lat2R) - sin(lat1R) * cos(lat2R) * cos(dLon)
        return atan2(y, x)
    }

    fun walkMinutes(distanceMeters: Double): Double = distanceMeters / Thresholds.WALK_SPEED

    fun formatWalkInfo(distanceMeters: Double, walkTimeSeconds: Double? = null): String {
        val walkMin = if (walkTimeSeconds != null) {
            (walkTimeSeconds / 60.0).toInt()
        } else {
            walkMinutes(distanceMeters).toInt()
        }
        val timeStr = if (walkMin < 1) "<1 min" else "$walkMin min"
        return "$timeStr walk - ${distanceMeters.toInt()}m"
    }

    fun hasMovedSignificantly(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double): Boolean {
        return abs(toLat - fromLat) > 0.0045 || abs(toLon - fromLon) > 0.006
    }
}
