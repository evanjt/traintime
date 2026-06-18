package com.evanjt.traintime.domain

import com.evanjt.traintime.Thresholds
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

object GeoUtils {
    // Flat-earth approximation, matches the Garmin and iOS implementations.
    fun haversineDistance(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double): Double {
        val dLat = (toLat - fromLat) * 111000.0
        val dLon = (toLon - fromLon) * 75700.0
        return sqrt(dLat * dLat + dLon * dLon)
    }

    // Great-circle bearing in radians.
    fun bearing(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double): Double {
        val dLon = Math.toRadians(toLon - fromLon)
        val lat1R = Math.toRadians(fromLat)
        val lat2R = Math.toRadians(toLat)
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
}
