package com.evanjt.traintime

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.evanjt.traintime.data.model.TransportMode

// Adaptive accent palette, ported from apple/TrainTimeWatch/Constants.swift.
// Plain text/secondary colours come from MaterialTheme.colorScheme instead so
// they follow the system light/dark theme; only the meaningful accents (minutes,
// delay, platform, favourites, tracking bar) live here.
data class AppPalette(
    val minutesNow: Color,
    val minutesSoon: Color,
    val delay: Color,
    val platform: Color,
    val platformChangedOrange: Color,
    val favouriteBackground: Color,
    val favouriteSeparator: Color,
    val favouriteStar: Color,
    val darkGreen: Color,
    val lightGreen: Color,
    val darkRed: Color,
    val amber: Color,
    val barGray: Color,
    val trackingBarBackground: Color,
    val ahead: Color,
    val onTime: Color,
    val behind: Color,
    // SBB-style line-pill fills (white text sits on top). Colour carries the
    // product category, not decoration. Deep enough for white text on both
    // light and dark backgrounds.
    val lineLongDistance: Color,
    val lineRegional: Color,
    val lineBus: Color,
    val lineTram: Color,
)

val LightPalette = AppPalette(
    minutesNow = Color(0xFFB58900),
    minutesSoon = Color(0xFF1E7D32),
    delay = Color(0xFFC73E00),
    platform = Color(0xFF0061C2),
    platformChangedOrange = Color(0xFFC53000),
    favouriteBackground = Color(0xFFF7EFD2),
    favouriteSeparator = Color(0xFFB89B00),
    favouriteStar = Color(0xFFA07800),
    darkGreen = Color(0xFF1E8E3E),
    lightGreen = Color(0xFF6FCF82),
    darkRed = Color(0xFFD32F2F),
    amber = Color(0xFFE08A00),
    barGray = Color(0xFFC7C7CC),
    trackingBarBackground = Color(0xFFE5E5EA),
    ahead = Color(0xFF1B7D2C),
    onTime = Color(0xFFB58900),
    behind = Color(0xFFC62828),
    lineLongDistance = Color(0xFFD5001C),
    lineRegional = Color(0xFF0061C2),
    lineBus = Color(0xFF4E6273),
    lineTram = Color(0xFF007A87),
)

val DarkPalette = AppPalette(
    minutesNow = Color(0xFFFFFF00),
    minutesSoon = Color(0xFF00FF00),
    delay = Color(0xFFFF5500),
    platform = Color(0xFF55AAFF),
    platformChangedOrange = Color(0xFFFF4400),
    favouriteBackground = Color(0xFF332800),
    favouriteSeparator = Color(0xFF998800),
    favouriteStar = Color(0xFFFFD700),
    darkGreen = Color(0xFF00FF00),
    lightGreen = Color(0xFF55FF55),
    darkRed = Color(0xFFFF0000),
    amber = Color(0xFFFFAA00),
    barGray = Color(0xFF444444),
    trackingBarBackground = Color.Black,
    ahead = Color(0xFF00FF00),
    onTime = Color(0xFFFFFF00),
    behind = Color(0xFFFF0000),
    lineLongDistance = Color(0xFFE63950),
    lineRegional = Color(0xFF2E86E0),
    lineBus = Color(0xFF6E8597),
    lineTram = Color(0xFF1AA2B0),
)

val LocalAppPalette = staticCompositionLocalOf { DarkPalette }

// Broad SBB product categories → line-pill fill. Long-distance vs regional by
// the line's letter prefix; number-only lines (bus/tram) fall back to the mode.
// One place to retune the mapping.
private val LONG_DISTANCE_PREFIXES =
    setOf("IC", "ICE", "EC", "ICN", "IR", "RJ", "RJX", "TGV", "EN", "NJ", "PE")

fun AppPalette.linePill(line: String, mode: TransportMode): Color {
    val prefix = line.takeWhile { it.isLetter() }.uppercase()
    return when {
        prefix.isEmpty() -> when (mode) {
            TransportMode.BUS -> lineBus
            TransportMode.TRAM -> lineTram
            else -> lineRegional
        }
        prefix in LONG_DISTANCE_PREFIXES -> lineLongDistance
        else -> lineRegional
    }
}

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
