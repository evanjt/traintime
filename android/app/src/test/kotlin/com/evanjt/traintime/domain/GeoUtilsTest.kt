package com.evanjt.traintime.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class GeoUtilsTest {
    @Test
    fun `haversine uses flat-earth factors`() {
        // One degree of latitude → 111000 m, matching Garmin/iOS.
        assertEquals(111000.0, GeoUtils.haversineDistance(46.0, 6.0, 47.0, 6.0), 0.1)
        assertEquals(75700.0, GeoUtils.haversineDistance(46.0, 6.0, 46.0, 7.0), 0.1)
    }

    @Test
    fun `bearing points north and east`() {
        assertEquals(0.0, GeoUtils.bearing(46.0, 6.0, 47.0, 6.0), 0.01)
        assertEquals(Math.PI / 2, GeoUtils.bearing(46.0, 6.0, 46.0, 6.1), 0.05)
    }

    @Test
    fun `walk info formats minutes and metres`() {
        assertEquals("2 min walk - 200m", GeoUtils.formatWalkInfo(200.0))
        assertEquals("<1 min walk - 50m", GeoUtils.formatWalkInfo(50.0))
        assertEquals("5 min walk - 100m", GeoUtils.formatWalkInfo(100.0, walkTimeSeconds = 300.0))
    }

    @Test
    fun `distance between real stations is deterministic and symmetric`() {
        // Place de la Planta -> Gare de Sion, ~376 m by the flat-earth model.
        val d = GeoUtils.haversineDistance(46.2306, 7.3576, 46.2275, 7.3596)
        assertEquals(376.0, d, 1.0)
        assertEquals(d, GeoUtils.haversineDistance(46.2275, 7.3596, 46.2306, 7.3576), 0.001)
    }

    @Test
    fun `distance is zero at the same point`() {
        assertEquals(0.0, GeoUtils.haversineDistance(46.2306, 7.3576, 46.2306, 7.3576), 0.001)
    }

    @Test
    fun `walk minutes derive from distance over walk speed`() {
        assertEquals(376.0 / 83.0, GeoUtils.walkMinutes(376.0), 0.001)
    }
}
