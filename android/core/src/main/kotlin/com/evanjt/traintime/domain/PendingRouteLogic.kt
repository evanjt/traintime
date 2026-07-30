package com.evanjt.traintime.domain

import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg

// Pure lifecycle rules for a pending route. Everything is derived from the
// clock, so the same call is safe on foreground, on timer ticks, and after
// tracking ends, event plumbing only makes advancement prompt, never
// correct. All functions take `now` explicitly for testability.
object PendingRouteLogic {
    // Matches the tracking session's departed rule so a leg isn't declared
    // missed while its session could still be running. Measured from the
    // effective departure, so a delayed train keeps its grace.
    const val GRACE_SEC = 90L

    // Notification lead for the first leg of a saved route: at least 15 min
    // before departure, more when a preceding walk leg needs it. Both leads are
    // user-configurable (Settings), the notifier passes the chosen value.
    const val MIN_LEAD_SEC = 15 * 60L
    const val WALK_MARGIN_SEC = 5 * 60L

    // Lead for a later connection, when the traveller is already moving. Much
    // shorter than the initial reminder and set independently.
    const val CONNECTION_LEAD_SEC = 3 * 60L

    // Cap on the first-leg lead so a distance-aware reminder saved from far away
    // never schedules absurdly early.
    const val MAX_LEAD_SEC = 90 * 60L

    // A route is only offered for one-tap resume this close to departure,
    // roughly when the train can appear on the 20-row board.
    const val RESUME_WINDOW_SEC = 45 * 60L

    // Advance the cursor past every ride leg that has already left. Null
    // means no viable leg remains and the route should be cleared. A route
    // mid-tracking whose leg is still viable is left untouched.
    fun normalize(route: PendingRoute, now: Long): PendingRoute? {
        var cursor = route.cursor
        while (cursor < route.legs.size) {
            val leg = route.legs[cursor]
            if (leg.type == LegType.RIDE && leg.depTs >= now - GRACE_SEC) break
            cursor++
        }
        if (cursor >= route.legs.size) return null
        return if (cursor == route.cursor) {
            route
        } else {
            route.copy(cursor = cursor, status = PendingRoute.STATUS_SAVED)
        }
    }

    // A ride leg with an earlier ride leg in the route is a connection: the
    // traveller has already boarded once, so a short reminder suffices.
    fun isConnectionLeg(route: PendingRoute): Boolean {
        if (route.cursor >= route.legs.size) return false
        return route.legs.take(route.cursor).any { it.type == LegType.RIDE }
    }

    // When userDistanceMeters is supplied (distance-aware mode), the first-leg
    // lead becomes the walk time to the origin station plus savedLeadSec as a
    // buffer, capped at MAX_LEAD_SEC. Null distance keeps the static behaviour.
    // Connection legs always use the short static connection lead.
    fun notifyTs(
        route: PendingRoute,
        savedLeadSec: Long = MIN_LEAD_SEC,
        connectionLeadSec: Long = CONNECTION_LEAD_SEC,
        userDistanceMeters: Double? = null,
    ): Long? {
        val leg = route.currentLeg ?: return null
        if (!leg.isTrackable || route.isLegMuted(route.cursor)) return null
        if (isConnectionLeg(route)) return leg.depTs - connectionLeadSec
        if (userDistanceMeters != null) {
            val walkSec = (GeoUtils.walkMinutes(userDistanceMeters) * 60).toLong()
            val lead = minOf(walkSec + savedLeadSec, MAX_LEAD_SEC)
            return leg.depTs - lead
        }
        val walk = route.legs.getOrNull(route.cursor - 1)
            ?.takeIf { it.type == LegType.WALK }
        val lead = maxOf(savedLeadSec, (walk?.durationSec ?: 0L) + WALK_MARGIN_SEC)
        return leg.depTs - lead
    }

    fun isResumable(route: PendingRoute, now: Long): Boolean {
        val leg = route.currentLeg ?: return false
        if (!leg.isTrackable || route.isLegMuted(route.cursor)) return false
        return leg.depTs - now <= RESUME_WINDOW_SEC && leg.depTs >= now - GRACE_SEC
    }

    // Same trip shared twice is idempotent; a different trip needs the
    // user's confirmation before replacing.
    fun fingerprint(route: PendingRoute): String = fingerprint(route.legs)

    fun fingerprint(legs: List<RouteLeg>): String {
        val leg = legs.firstOrNull { it.type == LegType.RIDE } ?: return ""
        return "${leg.trainNumber ?: "${leg.category}${leg.lineNumber}"}|${leg.depTs}"
    }

    // Tracking for `endedDepTs` finished (departed, or user exited). Only a
    // route that was tracking that exact leg reacts: after departure the
    // cursor moves on (normalize does the actual advancing), an early manual
    // exit reverts to saved on the same leg. Unrelated tracking sessions
    // never touch pending state.
    fun advancedAfterTracking(route: PendingRoute, endedDepTs: Long, now: Long): PendingRoute? {
        if (route.status != PendingRoute.STATUS_TRACKING) return route
        val leg = route.currentLeg ?: return normalize(route, now)
        if (leg.depTs != endedDepTs) return route
        return if (now < leg.depTs - GRACE_SEC) {
            route.copy(status = PendingRoute.STATUS_SAVED)
        } else {
            normalize(route.copy(cursor = route.cursor + 1, status = PendingRoute.STATUS_SAVED), now)
        }
    }
}
