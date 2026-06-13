package com.evanjt.traintime.data.api

import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Wire DTOs for api.traintime.ch. Field defaults mirror the lenient
// parsing in Departure.from(json:) on iOS.

@Serializable
data class DepartureDto(
    val to: String? = null,
    val category: String? = null,
    val number: String? = null,
    val departure: Long? = null,
    val delay: Int? = null,
    val platform: String? = null,
    val platformChanged: Boolean? = null,
    val trainNumber: String? = null,
    val operatorRef: String? = null,
) {
    fun toDeparture(nowEpochSeconds: Long): Departure {
        val minutesUntil = departure?.let { ((it - nowEpochSeconds) / 60).toInt() } ?: -1
        return Departure(
            destination = to ?: "?",
            minutesUntil = minutesUntil,
            departureTimestamp = departure,
            delay = delay?.takeIf { it > 0 } ?: 0,
            platform = platform ?: "",
            platformChanged = platformChanged ?: false,
            lineNumber = number ?: "",
            category = category ?: "",
            trainNumber = trainNumber,
            operatorRef = operatorRef,
        )
    }
}

@Serializable
data class StationDto(
    val id: String? = null,
    val name: String? = null,
    val lat: Double? = null,
    val lon: Double? = null,
    val dist: Double? = null,
    val departures: List<DepartureDto>? = null,
) {
    fun toStation(mode: TransportMode, nowEpochSeconds: Long): Station? {
        val id = id ?: return null
        val embedded = departures
            ?.takeIf { it.isNotEmpty() }
            ?.take(Thresholds.MAX_DEPARTURES)
            ?.map { it.toDeparture(nowEpochSeconds) }
        return Station(
            id = id,
            name = name,
            lat = lat,
            lon = lon,
            mode = mode,
            dist = dist,
            embeddedDepartures = embedded,
        )
    }
}

@Serializable
data class NearbyResponseDto(
    val train: List<StationDto> = emptyList(),
    val bus: List<StationDto> = emptyList(),
    val tram: List<StationDto> = emptyList(),
    val special: List<StationDto> = emptyList(),
)

@Serializable
data class DeparturesResponseDto(
    val departures: List<DepartureDto> = emptyList(),
    val favourites: List<DepartureDto>? = null,
)

@Serializable
data class FormationWagonDto(
    val position: Int? = null,
    val number: Int? = null,
    @SerialName("class") val wagonClass: Int? = null,
    val sector: String? = null,
    val features: List<String> = emptyList(),
    val closed: Boolean = false,
)

@Serializable
data class FormationResponseDto(
    val track: String = "",
    val sectors: List<String> = emptyList(),
    val wagons: List<FormationWagonDto>? = null,
) {
    fun toFormation(): Formation? {
        val wagons = wagons
            ?.mapNotNull { w ->
                val position = w.position ?: return@mapNotNull null
                val number = w.number ?: return@mapNotNull null
                val wagonClass = w.wagonClass ?: return@mapNotNull null
                FormationWagon(
                    position = position,
                    number = number,
                    wagonClass = wagonClass,
                    sector = w.sector ?: "",
                    features = w.features,
                    closed = w.closed,
                )
            }
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        return Formation(track = track, sectors = sectors, wagons = wagons)
    }
}
