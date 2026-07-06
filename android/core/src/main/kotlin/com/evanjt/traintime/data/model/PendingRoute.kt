package com.evanjt.traintime.data.model

import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import com.evanjt.traintime.data.sbb.SharedRoute
import kotlinx.serialization.Serializable

// A shared SBB route queued for later: the target leg wasn't on the live
// departure board yet (too far in the future), so tracking would have died
// on the first poll. Phone-owned; watches receive read-only mirrors.
@Serializable
data class PendingRoute(
    val id: String,
    val legs: List<RouteLeg>,
    val finalDestination: String,
    val cursor: Int = 0,
    val status: String = STATUS_SAVED,
    val createdTs: Long,
    val sourceUrl: String? = null,
    // Legs the user switched off in the route view: no reminder, no auto-resume
    // offer. The route stays visible and any leg can still be tracked by hand.
    val mutedLegIndices: List<Int> = emptyList(),
) {
    val currentLeg: RouteLeg?
        get() = legs.getOrNull(cursor)?.takeIf { it.type == LegType.RIDE }

    fun isLegMuted(index: Int): Boolean = index in mutedLegIndices

    companion object {
        const val STATUS_SAVED = "saved"
        const val STATUS_TRACKING = "tracking"

        fun from(
            route: SharedRoute,
            targetLegIndex: Int,
            id: String,
            createdTs: Long,
            sourceUrl: String? = null,
        ) = PendingRoute(
            id = id,
            legs = route.legs,
            finalDestination = route.finalDestinationName,
            cursor = targetLegIndex,
            createdTs = createdTs,
            sourceUrl = sourceUrl,
        )
    }
}
