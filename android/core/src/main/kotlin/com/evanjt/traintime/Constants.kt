package com.evanjt.traintime

// Pure (non-Compose) constants shared across :app and :wear. The adaptive
// colour palette stays in each UI module. These are the platform-neutral halves.

// Seconds, matching the iOS TimeInterval values.
object Timing {
    const val NORMAL_REFRESH_INTERVAL = 5.0
    const val TRACKING_REFRESH_INTERVAL = 1.0
    const val FETCH_COOLDOWN_NORMAL = 30.0
    const val FETCH_COOLDOWN_TRACKING = 10.0
    const val REQUEST_TIMEOUT = 30.0

    // Per-host attempt budget for the API client. A dead host is dropped at
    // the connect timeout, the last host in the list gets the long budget.
    const val CONNECT_TIMEOUT_SECONDS = 2L
    const val FIRST_ATTEMPT_TIMEOUT_SECONDS = 3L
    const val LAST_ATTEMPT_TIMEOUT_SECONDS = 10L
    const val PRIMARY_REPROBE_SECONDS = 300L
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

// Line pill geometry, one rule on every surface: the pill is a fixed width,
// in ems of the surface's chip font, that holds a FIT_CHARS label with the
// label centred. A longer label shrinks its font to fit rather than clip.
object LinePillGeometry {
    const val FIT_CHARS = 5

    // Five bold capitals or digits plus the pill's side padding.
    const val WIDTH_EMS = 4.2f

    // An unpadded label in a fixed column (the watch row's line text).
    const val TEXT_WIDTH_EMS = 3.4f

    fun fontScale(label: String): Float =
        if (label.length <= FIT_CHARS) 1f else FIT_CHARS.toFloat() / label.length
}
