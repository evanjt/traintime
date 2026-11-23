package com.evanjt.traintime.region

import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class RegionsTest {
    @Test
    fun pointsResolveToTheirRegion() {
        assertEquals(Regions.MELBOURNE, Regions.at(-37.8213, 145.0364))
        assertEquals(Regions.SWITZERLAND, Regions.at(46.9480, 7.4474))
        assertNull(Regions.at(-38.1499, 144.3617))
        assertNull(Regions.at(-33.8688, 151.2093))
    }

    @Test
    fun stationIdsResolveByPrefixWithBareIdsSwiss() {
        assertEquals(Regions.MELBOURNE, Regions.forStationId("au-vic-1080"))
        assertEquals(Regions.SWITZERLAND, Regions.forStationId("8503000"))
        assertEquals(Regions.SWITZERLAND, Regions.forStationId("zz-unknown-1"))
    }

    @Test
    fun melbourneSearchesInsteadOfShowingOutOfCoverage() {
        assertFalse(Regions.outOfCoverage(-37.8213, 145.0364, hasStations = false))
        assertTrue(Regions.isCovered(-37.8213, 145.0364))
        assertTrue(Regions.outOfCoverage(-33.8688, 151.2093, hasStations = false))
        assertFalse(Regions.outOfCoverage(-33.8688, 151.2093, hasStations = true))
        assertFalse(Regions.outOfCoverage(46.9480, 7.4474, hasStations = false))
    }

    @Test
    fun clockTimeReadsInTheStationRegionZone() {
        // 2026-11-22 10:38 UTC: 21:38 in Melbourne (AEDT), 11:38 in Bern (CET).
        val ts = 1_795_343_880L
        assertEquals("21:38", Regions.clockTime(ts, "au-vic-1080"))
        assertEquals("11:38", Regions.clockTime(ts, "8503000"))
        assertEquals(ZoneId.of("Australia/Melbourne"), Regions.zoneFor("au-vic-1080"))
    }

    @Test
    fun onlySwissRegionHasFormationAndSbbShare() {
        assertTrue(Regions.SWITZERLAND.formation)
        assertTrue(Regions.SWITZERLAND.sbbShare)
        assertFalse(Regions.MELBOURNE.formation)
        assertFalse(Regions.MELBOURNE.sbbShare)
    }

    @Test
    fun rideLegTracksOnlyWhereTheRegionTakesSbbShares() {
        fun ride(lat: Double, lon: Double) = RouteLeg(
            type = LegType.RIDE, originId = "1", originName = "A", originLat = lat, originLon = lon,
            destName = "B", depTs = 0, arrTs = 0,
        )
        assertTrue(ride(46.9480, 7.4474).isTrackable)
        assertFalse(ride(-37.8213, 145.0364).isTrackable)
        assertFalse(ride(-33.8688, 151.2093).isTrackable)
    }
}
