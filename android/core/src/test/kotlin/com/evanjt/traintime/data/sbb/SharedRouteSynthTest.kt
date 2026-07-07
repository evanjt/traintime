package com.evanjt.traintime.data.sbb

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedRouteSynthTest {
    private fun departure(ts: Long = 1_750_000_000L) = Departure(
        destination = "Brig",
        minutesUntil = 42,
        departureTimestamp = ts,
        delay = 0,
        platform = "3",
        platformChanged = false,
        lineNumber = "IR90",
        category = "IR",
        trainNumber = "1820",
        operatorRef = null,
    )

    private val bern = Station("8507000", "Bern", 46.9489, 7.4396, TransportMode.TRAIN)

    @Test
    fun synthesisedLegCarriesOriginAndDeparture() {
        val leg = SharedRoute.forDeparture(bern, departure()).legs.single()
        assertEquals(LegType.RIDE, leg.type)
        assertEquals("8507000", leg.originId)
        assertEquals(46.9489, leg.originLat!!, 1e-6)
        assertEquals("Brig", leg.destName)
        assertEquals(1_750_000_000L, leg.depTs)
        assertEquals(leg.depTs, leg.arrTs)
        // Concatenated board form kept, category null, so the chip renders "IR90".
        assertEquals("IR90", leg.lineNumber)
        assertNull(leg.category)
        assertEquals("1820", leg.trainNumber)
    }

    @Test
    fun synthesisedLegIsTrackableInSwitzerland() {
        assertTrue(SharedRoute.forDeparture(bern, departure()).legs.single().isTrackable)
    }

    @Test
    fun synthesisedLegRoundTripsThroughMatchDeparture() {
        val dep = departure()
        val leg = SharedRoute.forDeparture(bern, dep).legs.single()
        assertSame(dep, matchDeparture(listOf(dep), leg))
    }
}
