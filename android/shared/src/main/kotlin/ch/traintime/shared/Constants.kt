package ch.traintime.shared

object AppColors {
    const val STATION_NAME = 0xFFFFFFFF.toInt()
    const val WALK_INFO = 0xFFAAAAAA.toInt()
    const val SEPARATOR = 0xFF444444.toInt()
    const val MINUTES_GONE = 0xFF666666.toInt()
    const val MINUTES_NOW = 0xFFFFFF00.toInt()
    const val MINUTES_SOON = 0xFF00FF00.toInt()
    const val DELAY = 0xFFFF5500.toInt()
    const val PLATFORM = 0xFF55AAFF.toInt()
    const val PLATFORM_CHANGED = 0xFFFF0000.toInt()
    const val PLATFORM_CHANGED_TEXT = 0xFFFFFFFF.toInt()
    const val BODY_STATUS = 0xFFAAAAAA.toInt()
    const val BACKGROUND = 0xFF000000.toInt()
    const val SELECTION_HIGHLIGHT = 0xFF004488.toInt()
    const val SELECTION_ACCENT = 0xFF55AAFF.toInt()
    const val PLATFORM_CHANGED_ORANGE = 0xFFFF4400.toInt()
    const val DARK_GREEN = 0xFF00FF00.toInt()
    const val LIGHT_GREEN = 0xFF55FF55.toInt()
    const val DARK_RED = 0xFFFF0000.toInt()
    const val AMBER = 0xFFFFAA00.toInt()
    const val BAR_GRAY = 0xFF444444.toInt()
    const val AHEAD = 0xFF00FF00.toInt()
    const val ON_TIME = 0xFFFFFF00.toInt()
    const val BEHIND = 0xFFFF0000.toInt()
}

object SwissBounds {
    const val LAT_MIN = 45.8
    const val LAT_MAX = 47.8
    const val LON_MIN = 5.9
    const val LON_MAX = 10.5

    fun contains(lat: Double, lon: Double): Boolean =
        lat in LAT_MIN..LAT_MAX && lon in LON_MIN..LON_MAX
}

object Timing {
    const val NORMAL_REFRESH_INTERVAL = 5000L // ms
    const val TRACKING_REFRESH_INTERVAL = 1000L // ms
    const val FETCH_COOLDOWN_NORMAL = 30_000L // ms
    const val FETCH_COOLDOWN_TRACKING = 10_000L // ms
    const val REQUEST_TIMEOUT = 30_000L // ms
    const val INACTIVITY_TIMEOUT = 60_000L // ms
}

object Thresholds {
    const val MOVEMENT_THRESHOLD = 500.0 // meters
    const val WALK_SPEED = 83.0 // meters per minute
    const val BAR_SCALE = 3.0 // minutes mapped to half bar width
    const val MAX_STATIONS_PER_MODE = 5
    const val MAX_DEPARTURES = 20
    const val FALLBACK_SEARCH_RADIUS = 5000.0 // meters
    const val CONSECUTIVE_ERROR_LIMIT = 3
}
