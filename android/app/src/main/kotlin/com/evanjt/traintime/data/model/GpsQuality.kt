package com.evanjt.traintime.data.model

import androidx.compose.ui.graphics.Color

enum class GpsQuality {
    UNAVAILABLE,
    LAST_KNOWN,
    POOR,
    GOOD;

    val color: Color
        get() = when (this) {
            UNAVAILABLE -> Color.Red
            LAST_KNOWN -> Color.Gray
            POOR -> Color(0xFFFFA500)
            GOOD -> Color.Green
        }

    companion object {
        // Cached coordinates are reported as LAST_KNOWN by the caller, not here.
        fun from(accuracy: Double?): GpsQuality = when {
            accuracy == null -> UNAVAILABLE
            accuracy < 0 -> UNAVAILABLE
            accuracy > 30 -> POOR
            else -> GOOD
        }
    }
}
