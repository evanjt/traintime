package com.evanjt.traintime.data.model

// Whole minutes since a list served through an upstream outage was fetched,
// at least one, or null for a live list. The board labels the rows with it.
fun staleMinutes(fetchedAt: Long?, nowEpochSeconds: Long): Int? {
    fetchedAt ?: return null
    return ((nowEpochSeconds - fetchedAt) / 60).toInt().coerceAtLeast(1)
}
