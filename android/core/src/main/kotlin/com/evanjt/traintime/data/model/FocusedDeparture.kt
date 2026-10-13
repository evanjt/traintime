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
    // Set only when tracking a saved route: the route's final destination, so the
    // header can keep showing the train's own terminus while a "Tracking route to
    // X" subtext carries where the journey actually ends. Null for board taps.
    val routeDestination: String? = null,
) {
    fun secondsUntil(nowEpochSeconds: Long): Long = departureTimestamp - nowEpochSeconds

    fun minutesUntil(nowEpochSeconds: Long): Double = secondsUntil(nowEpochSeconds) / 60.0

    // Until the effective departure (schedule plus delay): what "has it left"
    // and the delay badge are measured against.
    fun effectiveSecondsUntil(nowEpochSeconds: Long): Long = secondsUntil(nowEpochSeconds) + delay * 60L

    fun effectiveMinutesUntil(nowEpochSeconds: Long): Double = effectiveSecondsUntil(nowEpochSeconds) / 60.0

    // Matches the Garmin countdown formatting. Counts to the schedule, with the
    // delay badge beside it, and reads "now" from the scheduled minute until the
    // effective time has passed. Callers pass the localised words.
    fun countdownText(nowEpochSeconds: Long, departed: String = "Departed", nowText: String = "now"): String {
        val secs = secondsUntil(nowEpochSeconds)
        if (effectiveSecondsUntil(nowEpochSeconds) < -30) return departed
        if (secs < 5) return nowText
        val totalMin = secs / 60
        val remSec = secs % 60
        return if (totalMin < 3) {
            "%d:%02d".format(totalMin, remSec)
        } else {
            "$totalMin min"
        }
    }
}
