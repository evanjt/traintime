package com.evanjt.traintime.data.model

// Port of apple/TrainTimeWatch/Models/Departure.swift.
// minutesUntil is computed once at parse time, matching the iOS snapshot
// behaviour; precise tracking uses departureTimestamp directly.
data class Departure(
    val destination: String,
    val minutesUntil: Int,
    val departureTimestamp: Long?,
    val delay: Int,
    val platform: String,
    val platformChanged: Boolean,
    val lineNumber: String,
    val category: String,
    val trainNumber: String?,
    val operatorRef: String?,
) {
    val isGone: Boolean get() = minutesUntil < 0

    // Identity stable across fetches (the triple matches how favourites dedupe),
    // so Compose list keys don't churn when a fresh fetch replaces the list.
    val stableId: String get() = "${departureTimestamp ?: 0}|$lineNumber|$destination"

    fun secondsUntil(nowEpochSeconds: Long): Long? =
        departureTimestamp?.let { it - nowEpochSeconds }

    val minutesText: String
        get() = when {
            isGone -> "gone"
            minutesUntil == 0 -> "now"
            else -> "$minutesUntil'"
        }
}
