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
}
