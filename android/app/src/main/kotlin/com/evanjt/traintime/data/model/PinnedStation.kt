package com.evanjt.traintime.data.model

import kotlinx.serialization.Serializable

// A station the user has pinned ("My stations"). Stored with its coordinates so
// proximity can be computed offline (the Garmin glance picks the nearest pinned
// station from cached location). Keyed by station id.
@Serializable
data class PinnedStation(
    val id: String,
    val name: String,
    val lat: Double? = null,
    val lon: Double? = null,
)
