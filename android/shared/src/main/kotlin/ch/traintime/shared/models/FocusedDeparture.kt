package ch.traintime.shared.models

data class FocusedDeparture(
    val destination: String,
    val departureTimestamp: Int,
    var delay: Int,
    var platform: String,
    var platformChanged: Boolean
) {
    val secondsUntil: Int
        get() = departureTimestamp - (System.currentTimeMillis() / 1000).toInt()

    val minutesUntil: Double
        get() = secondsUntil.toDouble() / 60.0

    val countdownText: String
        get() {
            val secs = secondsUntil
            return when {
                secs < -30 -> "Departed"
                secs < 5 -> "now"
                secs / 60 < 3 -> {
                    val totalMin = secs / 60
                    val remSec = secs % 60
                    String.format("%d:%02d", totalMin, remSec)
                }
                else -> "${secs / 60} min"
            }
        }
}
