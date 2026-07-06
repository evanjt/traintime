package com.evanjt.traintime.data.model

// Pure model, the quality→colour mapping lives in each UI module (phone theme,
// wear theme) so this stays free of Compose.
enum class GpsQuality {
    UNAVAILABLE,
    LAST_KNOWN,
    POOR,
    GOOD;

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
