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

    // Identity stable across fetches, so Compose list keys don't churn when a
    // fresh fetch replaces the list. Includes trainNumber because OJP can list
    // distinct journeys in the same minute; excludes platform, which mutates
    // across fetches (platformChanged) and would churn keys.
    val stableId: String get() = "${departureTimestamp ?: 0}|$lineNumber|$destination|${trainNumber ?: ""}"

    fun secondsUntil(nowEpochSeconds: Long): Long? =
        departureTimestamp?.let { it - nowEpochSeconds }

    val minutesText: String
        get() = when {
            isGone -> "gone"
            minutesUntil == 0 -> "now"
            else -> "$minutesUntil'"
        }
}

// OJP can publish the same physical train twice under different journey numbers
// (seen live: Léman Express RL4 → Coppet as 23153 and 93153, only one carrying
// the real-time delay). Collapse rows a passenger can't tell apart, keeping the
// delay-bearing one. The key deliberately excludes trainNumber — it is the field
// that differs on such twins.
fun List<Departure>.dedupedForDisplay(): List<Departure> {
    if (size < 2) return this
    val best = LinkedHashMap<String, Departure>(size)
    for (dep in this) {
        val key = "${dep.departureTimestamp ?: 0}|${dep.lineNumber}|${dep.destination}|${dep.platform}"
        val existing = best[key]
        if (existing == null || dep.delay > existing.delay) best[key] = dep
    }
    return best.values.toList()
}
