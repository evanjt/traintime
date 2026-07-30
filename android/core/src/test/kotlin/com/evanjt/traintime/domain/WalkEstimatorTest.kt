package com.evanjt.traintime.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Scenario: background location is refused or the phone has been asleep, so the
// only fix available is old. Expected behaviour: a session keeps a usable walk
// margin from the last known position, and never loses the fix entirely.
class WalkEstimatorTest {
    private val stationLat = 46.9480
    private val stationLon = 7.4474

    // ~1 km north of the station.
    private val nearby = 46.9570 to 7.4474

    @Test
    fun freshFixMeasuresFromTheFix() {
        val estimate = WalkEstimator.estimate(
            Fix(nearby.first, nearby.second, ageMs = 0),
            stationLat,
            stationLon,
            fallbackMeters = 5000.0,
        )
        assertTrue(estimate.fresh)
        assertEquals(1000.0, estimate.distanceMeters!!, 50.0)
    }

    @Test
    fun staleFixIsStillUsedButNotFresh() {
        val estimate = WalkEstimator.estimate(
            Fix(nearby.first, nearby.second, ageMs = 6 * 60 * 60 * 1000L),
            stationLat,
            stationLon,
            fallbackMeters = null,
        )
        assertFalse(estimate.fresh)
        assertTrue(estimate.known)
        assertEquals(1000.0, estimate.distanceMeters!!, 50.0)
    }

    @Test
    fun boundaryFixCountsAsStale() {
        val fresh = WalkEstimator.estimate(
            Fix(nearby.first, nearby.second, WalkEstimator.FRESH_MAX_AGE_MS - 1),
            stationLat,
            stationLon,
            null,
        )
        val stale = WalkEstimator.estimate(
            Fix(nearby.first, nearby.second, WalkEstimator.FRESH_MAX_AGE_MS),
            stationLat,
            stationLon,
            null,
        )
        assertTrue(fresh.fresh)
        assertFalse(stale.fresh)
    }

    @Test
    fun noFixFallsBackToTheCarriedDistance() {
        val estimate = WalkEstimator.estimate(null, stationLat, stationLon, fallbackMeters = 420.0)
        assertEquals(420.0, estimate.distanceMeters!!, 0.001)
        assertFalse(estimate.fresh)
        assertTrue(estimate.known)
    }

    @Test
    fun missingStationCoordinatesFallBack() {
        val estimate = WalkEstimator.estimate(
            Fix(nearby.first, nearby.second, ageMs = 0),
            stationLat = null,
            stationLon = null,
            fallbackMeters = 300.0,
        )
        assertEquals(300.0, estimate.distanceMeters!!, 0.001)
        assertFalse(estimate.fresh)
    }

    // Nothing at all: the walk drops out, and the caller renders the no-GPS
    // state rather than failing.
    @Test
    fun nothingKnownYieldsNoEstimate() {
        val estimate = WalkEstimator.estimate(null, null, null, null)
        assertNull(estimate.distanceMeters)
        assertFalse(estimate.known)
        assertFalse(estimate.fresh)
    }
}
