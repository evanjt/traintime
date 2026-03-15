package ch.traintime.shared.models

enum class GPSQuality(val colorInt: Int) {
    UNAVAILABLE(0xFFFF0000.toInt()),
    LAST_KNOWN(0xFF888888.toInt()),
    POOR(0xFFFF8800.toInt()),
    GOOD(0xFF00FF00.toInt());

    companion object {
        fun from(accuracy: Float?): GPSQuality {
            if (accuracy == null) return UNAVAILABLE
            if (accuracy < 0) return UNAVAILABLE
            if (accuracy > 100) return POOR
            if (accuracy > 30) return POOR
            return GOOD
        }
    }
}
