package com.evanjt.traintime

// Pure (non-Compose) constants shared across :app and :wear. The adaptive
// colour palette stays in each UI module — these are the platform-neutral halves.

object SwissBounds {
    const val LAT_MIN = 45.8
    const val LAT_MAX = 47.8
    const val LON_MIN = 5.9
    const val LON_MAX = 10.5

    fun contains(lat: Double, lon: Double): Boolean =
        lat in LAT_MIN..LAT_MAX && lon in LON_MIN..LON_MAX
}

// Seconds, matching the iOS TimeInterval values.
object Timing {
    const val NORMAL_REFRESH_INTERVAL = 5.0
    const val TRACKING_REFRESH_INTERVAL = 1.0
    const val FETCH_COOLDOWN_NORMAL = 30.0
    const val FETCH_COOLDOWN_TRACKING = 10.0
    const val REQUEST_TIMEOUT = 30.0
    const val INACTIVITY_TIMEOUT = 60.0

    // Widget tap-to-activate window (matches the iOS provider's 5 min).
    const val WIDGET_ACTIVE_WINDOW = 300L
}

object Thresholds {
    const val WALK_SPEED = 83.0 // metres per minute
    const val BAR_SCALE = 3.0 // minutes mapped to half bar width
    const val MAX_STATIONS_PER_MODE = 5
    const val MAX_DEPARTURES = 20
    const val CONSECUTIVE_ERROR_LIMIT = 3
}
