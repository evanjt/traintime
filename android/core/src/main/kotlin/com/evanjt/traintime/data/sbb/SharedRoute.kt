package com.evanjt.traintime.data.sbb

import com.evanjt.traintime.SwissBounds
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Station
import kotlinx.serialization.Serializable

enum class LegType { RIDE, WALK }

// One leg of a shared SBB Mobile trip. Ride legs carry the train identity
// split as the recon publishes it: category "IR", lineNumber "90",
// trainNumber "1820". Departure.lineNumber is the concatenated "IR90" form,
// so matching normalises (see matchDeparture).
@Serializable
data class RouteLeg(
    val type: LegType,
    val originId: String? = null,
    val originName: String,
    val originLat: Double? = null,
    val originLon: Double? = null,
    val destId: String? = null,
    val destName: String,
    val destLat: Double? = null,
    val destLon: Double? = null,
    val depTs: Long,
    val arrTs: Long,
    val category: String? = null,
    val lineNumber: String? = null,
    val trainNumber: String? = null,
) {
    val durationSec: Long get() = arrTs - depTs

    // A leg can only be live-tracked if it's a Swiss ride with a station id.
    // Walk legs and connections outside Switzerland have no departure board.
    val isTrackable: Boolean
        get() = type == LegType.RIDE && originId != null &&
            originLat != null && originLon != null &&
            SwissBounds.contains(originLat, originLon)
}

data class SharedRoute(
    val legs: List<RouteLeg>,
    val sourceBlob: String,
) {
    // Where the trip actually ends, the last leg's destination, walk included
    // ("Lausanne, gare"), not the last train's alighting stop ("Lausanne").
    val finalDestinationName: String
        get() = legs.last().destName

    // The leg worth acting on now. First ride leg still catchable (60s grace
    // matches the "now" display threshold); a departed leg is skipped, so
    // mid-route shares naturally select the next connection. Null when every
    // ride has left, trip underway on its last leg or finished.
    fun targetRideLegIndex(nowEpochSeconds: Long): Int? {
        val index = legs.indexOfFirst {
            it.type == LegType.RIDE && it.depTs >= nowEpochSeconds - 60
        }
        return if (index >= 0) index else null
    }

    companion object {
        // A one-leg route synthesised from a live board departure, so a departure
        // can be saved for a reminder without an SBB share. Origin (id + coords)
        // comes from the station whose board it is; that's what the distance-aware
        // reminder needs. Peer of SharedRoute.forDeparture in SharedRoute.swift.
        fun forDeparture(station: Station, departure: Departure): SharedRoute =
            single(
                originId = station.id,
                originName = station.name ?: "",
                originLat = station.lat,
                originLon = station.lon,
                destName = departure.destination,
                depTs = departure.departureTimestamp ?: 0L,
                lineNumber = departure.lineNumber,
                trainNumber = departure.trainNumber,
            )

        // The single-ride-leg builder shared by the board save and the watch's
        // remind-on-phone command. lineNumber keeps the concatenated board form
        // ("IR90") with category null, so the chip/fingerprint render it directly
        // and matchDeparture still round-trips it; arrTs = depTs (unused for a
        // single first leg).
        fun single(
            originId: String?,
            originName: String,
            originLat: Double?,
            originLon: Double?,
            destName: String,
            depTs: Long,
            lineNumber: String,
            trainNumber: String?,
        ): SharedRoute {
            val leg = RouteLeg(
                type = LegType.RIDE,
                originId = originId,
                originName = originName,
                originLat = originLat,
                originLon = originLon,
                destName = destName,
                depTs = depTs,
                arrTs = depTs,
                category = null,
                lineNumber = lineNumber,
                trainNumber = trainNumber,
            )
            return SharedRoute(legs = listOf(leg), sourceBlob = "")
        }
    }
}
