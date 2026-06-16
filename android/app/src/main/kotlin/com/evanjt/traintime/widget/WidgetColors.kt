package com.evanjt.traintime.widget

import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProvider
import com.evanjt.traintime.data.model.TransportMode

// Day/night colour providers for the Glance widget, mirroring the app's
// adaptive AppPalette. Glance resolves day vs night per the system theme.
object WidgetColors {
    val background = ColorProvider(day = Color.White, night = Color.Black)
    val onSurface = ColorProvider(day = Color.Black, night = Color.White)
    val secondary = ColorProvider(day = Color(0xFF6D6D72), night = Color(0xFFAAAAAA))
    val divider = ColorProvider(day = Color(0xFFD1D1D6), night = Color(0xFF333333))

    val minutesNow = ColorProvider(day = Color(0xFFB58900), night = Color(0xFFFFFF00))
    val minutesSoon = ColorProvider(day = Color(0xFF1E7D32), night = Color(0xFF00FF00))
    val delay = ColorProvider(day = Color(0xFFC73E00), night = Color(0xFFFF5500))
    val platform = ColorProvider(day = Color(0xFF0061C2), night = Color(0xFF55AAFF))
    val platformChanged = ColorProvider(day = Color(0xFFD32F2F), night = Color(0xFFFF3B30))

    val favouriteBackground = ColorProvider(day = Color(0xFFF7EFD2), night = Color(0xFF332800))
    val favouriteSeparator = ColorProvider(day = Color(0xFFB89B00), night = Color(0xFF998800))
    val favouriteStar = ColorProvider(day = Color(0xFFA07800), night = Color(0xFFFFD700))

    val accent = ColorProvider(day = Color(0xFF0061C2), night = Color(0xFF55AAFF))

    // SBB-style line-pill fills, mirroring the app's AppPalette mapping.
    val lineLongDistance = ColorProvider(day = Color(0xFFD5001C), night = Color(0xFFE63950))
    val lineRegional = ColorProvider(day = Color(0xFF0061C2), night = Color(0xFF2E86E0))
    val lineBus = ColorProvider(day = Color(0xFF4E6273), night = Color(0xFF6E8597))
    val lineTram = ColorProvider(day = Color(0xFF007A87), night = Color(0xFF1AA2B0))

    private val LONG_DISTANCE_PREFIXES =
        setOf("IC", "ICE", "EC", "ICN", "IR", "RJ", "RJX", "TGV", "EN", "NJ", "PE")

    fun linePill(line: String, mode: TransportMode): androidx.glance.unit.ColorProvider {
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
}
