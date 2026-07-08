package com.evanjt.traintime.core.sync

import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import org.junit.Assert.assertEquals
import org.junit.Test

class TrackCommandTest {
    private val leg = RouteLeg(
        type = LegType.RIDE,
        originId = "8507000",
        originName = "Bern",
        originLat = 46.9490,
        originLon = 7.4390,
        destId = "8501120",
        destName = "Lausanne",
        depTs = 1_800_000_540L,
        arrTs = 1_800_004_140L,
        category = "IC",
        lineNumber = "1",
        trainNumber = "820",
    )

    @Test
    fun `fromLeg maps a ride leg to the Garmin track payload`() {
        val map = TrackCommand.fromLeg(leg, finalDestination = "Genève").toGarminMap()

        assertEquals("track", map["action"])
        // dest is the route's final destination, matching the reminder headsign,
        // not the leg's alighting stop (Lausanne).
        assertEquals("Genève", map["dest"])
        assertEquals(1_800_000_540L, map["depTs"])
        assertEquals("1", map["line"])
        assertEquals("IC", map["cat"])
        assertEquals("820", map["trainNum"])
        assertEquals("8507000", map["stId"])
        assertEquals(0, map["delay"])
        assertEquals("", map["plat"])
    }

    @Test
    fun `fromLeg tolerates a leg missing line and category`() {
        val bare = leg.copy(category = null, lineNumber = null, trainNumber = null)
        val map = TrackCommand.fromLeg(bare, finalDestination = "Lausanne").toGarminMap()

        assertEquals("", map["line"])
        assertEquals("", map["cat"])
        // trainNum is dropped from the payload when absent (buses / trams).
        assertEquals(false, map.containsKey("trainNum"))
    }
}
