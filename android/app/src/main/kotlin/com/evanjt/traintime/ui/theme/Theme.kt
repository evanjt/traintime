package com.evanjt.traintime.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import com.evanjt.traintime.DarkPalette
import com.evanjt.traintime.LightPalette
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.GpsQuality

// GPS quality → indicator tint. Lives in the UI layer so GpsQuality stays
// Compose-free in :core.
val GpsQuality.tint: Color
    get() = when (this) {
        GpsQuality.UNAVAILABLE -> Color.Red
        GpsQuality.LAST_KNOWN -> Color.Gray
        GpsQuality.POOR -> Color(0xFFFFA500)
        GpsQuality.GOOD -> Color.Green
    }

// Pure black/white backgrounds match iOS's systemBackground (the watch-first
// look in dark, a clean white in light).
private val DarkColors = darkColorScheme(
    primary = Color(0xFF55AAFF),
    background = Color.Black,
    surface = Color.Black,
    onPrimary = Color.Black,
    onBackground = Color.White,
    onSurface = Color.White,
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF0061C2),
    background = Color.White,
    surface = Color.White,
    onPrimary = Color.White,
    onBackground = Color.Black,
    onSurface = Color.Black,
)

@Composable
fun TrainTimeTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    CompositionLocalProvider(LocalAppPalette provides if (dark) DarkPalette else LightPalette) {
        MaterialTheme(
            colorScheme = if (dark) DarkColors else LightColors,
            content = content,
        )
    }
}
