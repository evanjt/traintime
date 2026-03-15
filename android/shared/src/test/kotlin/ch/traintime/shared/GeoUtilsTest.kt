package ch.traintime.shared

import ch.traintime.shared.geo.GeoUtils
import org.junit.Assert.*
import org.junit.Test

class GeoUtilsTest {
    @Test
    fun `haversine distance between same point is zero`() {
        val dist = GeoUtils.haversineDistance(47.0, 7.0, 47.0, 7.0)
        assertEquals(0.0, dist, 0.001)
    }

    @Test
    fun `haversine distance is positive`() {
        val dist = GeoUtils.haversineDistance(46.9, 7.4, 47.0, 7.5)
        assertTrue(dist > 0)
    }

    @Test
    fun `walk minutes at 83 meters per minute`() {
        val minutes = GeoUtils.walkMinutes(830.0)
        assertEquals(10.0, minutes, 0.001)
    }

    @Test
    fun `format walk info under 1 minute`() {
        val info = GeoUtils.formatWalkInfo(50.0)
        assertEquals("<1 min walk - 50m", info)
    }

    @Test
    fun `format walk info over 1 minute`() {
        val info = GeoUtils.formatWalkInfo(500.0)
        assertEquals("6 min walk - 500m", info)
    }

    @Test
    fun `format walk info with walk time override`() {
        val info = GeoUtils.formatWalkInfo(500.0, 300.0)
        assertEquals("5 min walk - 500m", info)
    }

    @Test
    fun `has moved significantly latitude`() {
        assertTrue(GeoUtils.hasMovedSignificantly(47.0, 7.0, 47.005, 7.0))
    }

    @Test
    fun `has not moved significantly`() {
        assertFalse(GeoUtils.hasMovedSignificantly(47.0, 7.0, 47.001, 7.001))
    }

    @Test
    fun `swiss bounds contains Bern`() {
        assertTrue(SwissBounds.contains(46.948, 7.447))
    }

    @Test
    fun `swiss bounds does not contain Berlin`() {
        assertFalse(SwissBounds.contains(52.520, 13.405))
    }
}
