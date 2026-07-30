package com.evanjt.traintime.domain

// A location fix and how old it is. Age is measured on the monotonic clock, so
// it survives wall-clock changes.
data class Fix(val lat: Double, val lon: Double, val ageMs: Long)

// Walk distance to the station, and whether it came from a current fix.
// `fresh = false` means the number is a last-known estimate: still worth
// showing, but the user may have moved since.
data class WalkEstimate(val distanceMeters: Double?, val fresh: Boolean) {
    val known: Boolean get() = distanceMeters != null
}

// Background location is commonly refused, and a tracking session must survive
// that: a stale fix beats no margin at all, and no fix at all must still leave
// the countdown, delay and platform working. Pure so the fallback ladder is
// testable without a location provider.
object WalkEstimator {
    const val FRESH_MAX_AGE_MS = 3 * 60 * 1000L

    // Past this the number is not a walk and the ahead/behind verdict derived
    // from it is meaningless: a wrong or wildly outdated fix would otherwise
    // render as "119542 min behind" rather than simply no walk estimate.
    const val MAX_PLAUSIBLE_METERS = 20_000.0

    // Ladder: a fix plus station coordinates gives a real distance (fresh or
    // not), otherwise fall back to whatever distance was last carried on the
    // session, otherwise nothing.
    fun estimate(
        fix: Fix?,
        stationLat: Double?,
        stationLon: Double?,
        fallbackMeters: Double?,
    ): WalkEstimate {
        if (fix != null && stationLat != null && stationLon != null) {
            val distance = GeoUtils.haversineDistance(fix.lat, fix.lon, stationLat, stationLon)
            if (distance <= MAX_PLAUSIBLE_METERS) {
                return WalkEstimate(distance, fix.ageMs < FRESH_MAX_AGE_MS)
            }
            return WalkEstimate(null, false)
        }
        return WalkEstimate(fallbackMeters?.takeIf { it <= MAX_PLAUSIBLE_METERS }, false)
    }
}
