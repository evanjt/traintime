package com.evanjt.traintime.core.sync

import com.evanjt.traintime.data.model.FocusedDeparture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class TrackCommandTest {
    private val focused = FocusedDeparture(
        destination = "Bern",
        departureTimestamp = 1_750_000_540L,
        lineNumber = "IC1",
        category = "IC",
        trainNumber = "817",
        operatorRef = "11",
        delay = 2,
        platform = "7",
        platformChanged = false,
    )

    @Test
    fun focusedDepartureRoundTripsThroughWireFormat() {
        val cmd = TrackCommand.from(focused, "8507000")
        val decoded = WearSync.decodeTrack(WearSync.encodeTrack(cmd))!!
        assertEquals(cmd, decoded)
        assertEquals(focused, decoded.toFocusedDeparture())
        assertEquals("8507000", decoded.stationId)
    }

    @Test
    fun garminMapOmitsAbsentOptionals() {
        val map = TrackCommand.from(focused.copy(trainNumber = null, operatorRef = null), null).toGarminMap()
        assertEquals("track", map["action"])
        assertEquals("IC", map["cat"])
        assertFalse(map.containsKey("trainNum"))
        assertFalse(map.containsKey("opRef"))
        assertFalse(map.containsKey("stId"))
    }
}
