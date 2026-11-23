package com.evanjt.traintime.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.evanjt.traintime.LinePillGeometry
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.data.model.TransportMode

// Wear-side accent palette, the same meaningful colours as the phone's
// AppPalette (minutes, delay, platform, favourites, tracking bar), defined here
// so :core stays Compose-free and :wear owns its own theme.
data class WearPalette(
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
    val lineLongDistance: Color,
    val lineRegional: Color,
    val lineBus: Color,
    val lineTram: Color,
)

val WearLightPalette = WearPalette(
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

val WearDarkPalette = WearPalette(
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

val LocalWearPalette = staticCompositionLocalOf { WearDarkPalette }

private val LONG_DISTANCE_PREFIXES =
    setOf("IC", "ICE", "EC", "ICN", "IR", "RJ", "RJX", "TGV", "EN", "NJ", "PE")

fun WearPalette.linePill(line: String, mode: TransportMode): Color {
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

// The watch line pill, the phone's rule at the watch chip font: a fixed width
// that holds a five-character label, centred, shrunk when it runs longer.
@Composable
fun WearLinePill(
    label: String,
    fill: Color,
    fontSize: TextUnit,
    modifier: Modifier = Modifier,
    verticalPadding: Dp = 1.dp,
) {
    val width = with(LocalDensity.current) { (fontSize * LinePillGeometry.WIDTH_EMS).toDp() }
    Text(
        label,
        color = Color.White,
        fontSize = fontSize * LinePillGeometry.fontScale(label),
        fontWeight = FontWeight.Bold,
        textAlign = TextAlign.Center,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Clip,
        modifier = modifier
            .width(width)
            .clip(RoundedCornerShape(6.dp))
            .background(fill)
            .padding(vertical = verticalPadding),
    )
}

val GpsQuality.tint: Color
    get() = when (this) {
        GpsQuality.UNAVAILABLE -> Color.Red
        GpsQuality.LAST_KNOWN -> Color.Gray
        GpsQuality.POOR -> Color(0xFFFFA500)
        GpsQuality.GOOD -> Color.Green
    }

@Composable
fun TrainTimeWearTheme(content: @Composable () -> Unit) {
    // Wear's MaterialTheme is a dark scheme (black background, white text) and
    // watches run dark by default, so always pair it with the dark palette,
    // otherwise the light favourite background renders under white text.
    CompositionLocalProvider(LocalWearPalette provides WearDarkPalette) {
        MaterialTheme(content = content)
    }
}
