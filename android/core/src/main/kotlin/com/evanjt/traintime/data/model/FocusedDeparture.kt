package com.evanjt.traintime.data.model

// Port of apple/TrainTimeWatch/Models/FocusedDeparture.swift.
// The countdown is fully local: derived from departureTimestamp, so it
// keeps running when the API is unreachable.
data class FocusedDeparture(
    val destination: String,
    val departureTimestamp: Long,
    val lineNumber: String,
    val category: String,
    val trainNumber: String?,
    val operatorRef: String?,
    val delay: Int,
    val platform: String,
    val platformChanged: Boolean,
) {
    fun secondsUntil(nowEpochSeconds: Long): Long = departureTimestamp - nowEpochSeconds

    fun minutesUntil(nowEpochSeconds: Long): Double = secondsUntil(nowEpochSeconds) / 60.0

    // Matches the Garmin countdown formatting.
    fun countdownText(nowEpochSeconds: Long): String {
        val secs = secondsUntil(nowEpochSeconds)
        if (secs < -30) return "Departed"
        if (secs < 5) return "now"
        val totalMin = secs / 60
        val remSec = secs % 60
        return if (totalMin < 3) {
            "%d:%02d".format(totalMin, remSec)
        } else {
            "$totalMin min"
        }
    }
}
