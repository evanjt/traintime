package com.evanjt.traintime.data.model

import org.junit.Assert.assertEquals
import org.junit.Test

class FocusedDepartureTest {
    private val now = 1718000000L

    private fun focused(departsInSeconds: Long) = FocusedDeparture(
        destination = "Brig",
        departureTimestamp = now + departsInSeconds,
        lineNumber = "IC8",
        category = "IC",
        trainNumber = "823",
        operatorRef = "SBB",
        delay = 0,
        platform = "3",
        platformChanged = false,
    )

    @Test
    fun `counts down in minute-second format under three minutes`() {
        assertEquals("2:05", focused(125).countdownText(now))
        assertEquals("0:59", focused(59).countdownText(now))
    }

    @Test
    fun `shows whole minutes from three minutes up`() {
        assertEquals("3 min", focused(180).countdownText(now))
        assertEquals("12 min", focused(720).countdownText(now))
    }

    @Test
    fun `shows now just before departure`() {
        assertEquals("now", focused(4).countdownText(now))
        assertEquals("now", focused(0).countdownText(now))
        assertEquals("now", focused(-30).countdownText(now))
    }

    @Test
    fun `shows departed after half a minute`() {
        assertEquals("Departed", focused(-31).countdownText(now))
    }

    @Test
    fun `minutesUntil is fractional`() {
        assertEquals(1.5, focused(90).minutesUntil(now), 0.0001)
        assertEquals(-1.0, focused(-60).minutesUntil(now), 0.0001)
    }
}
