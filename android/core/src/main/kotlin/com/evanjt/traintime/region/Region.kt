package com.evanjt.traintime.region

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class Bounds(val latMin: Double, val latMax: Double, val lonMin: Double, val lonMax: Double) {
    fun contains(lat: Double, lon: Double): Boolean = lat in latMin..latMax && lon in lonMin..lonMax
}

// A covered area. Station ids carry the region's prefix; Swiss ids are bare.
// formation: the backend serves train formations there. sbbShare: SBB Mobile
// trip shares can be live-tracked there. The list matches the backend's and
// the other clients' region lists entry for entry.
data class Region(
    val id: String,
    val bounds: Bounds,
    val zone: ZoneId,
    val idPrefix: String,
    val formation: Boolean,
    val sbbShare: Boolean,
)

object Regions {
    val SWITZERLAND = Region(
        id = "ch",
        bounds = Bounds(latMin = 45.8, latMax = 47.8, lonMin = 5.9, lonMax = 10.5),
        zone = ZoneId.of("Europe/Zurich"),
        idPrefix = "",
        formation = true,
        sbbShare = true,
    )

    val MELBOURNE = Region(
        id = "au-vic",
        bounds = Bounds(latMin = -38.50, latMax = -37.40, lonMin = 144.40, lonMax = 145.70),
        zone = ZoneId.of("Australia/Melbourne"),
        idPrefix = "au-vic-",
        formation = false,
        sbbShare = false,
    )

    val ALL: List<Region> = listOf(SWITZERLAND, MELBOURNE)

    fun at(lat: Double, lon: Double): Region? = ALL.firstOrNull { it.bounds.contains(lat, lon) }

    fun isCovered(lat: Double, lon: Double): Boolean = at(lat, lon) != null

    // The out-of-coverage status shows only while no stations are loaded.
    fun outOfCoverage(lat: Double, lon: Double, hasStations: Boolean): Boolean =
        !hasStations && !isCovered(lat, lon)

    // Longest matching prefix; a bare or unknown id is Swiss.
    fun forStationId(id: String): Region =
        ALL.filter { it.idPrefix.isNotEmpty() && id.startsWith(it.idPrefix) }
            .maxByOrNull { it.idPrefix.length } ?: SWITZERLAND

    // A departure reads in its station's local time; with no station known,
    // the device zone.
    fun zoneFor(stationId: String?): ZoneId =
        stationId?.let { forStationId(it).zone } ?: ZoneId.systemDefault()

    private val HHMM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    fun clockTime(epochSeconds: Long, stationId: String?): String =
        HHMM.format(Instant.ofEpochSecond(epochSeconds).atZone(zoneFor(stationId)))
}
