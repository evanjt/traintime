package com.evanjt.traintime.data.model

import com.evanjt.traintime.domain.GeoUtils

data class Station(
    val id: String,
    val name: String?,
    val lat: Double?,
    val lon: Double?,
    val mode: TransportMode,
    val dist: Double? = null,
    val embeddedDepartures: List<Departure>? = null,
) {
    fun walkInfo(index: Int, total: Int): String {
        val base = GeoUtils.formatWalkInfo(dist ?: 0.0)
        return if (total > 1) "$base  ${index + 1}/$total" else base
    }
}
