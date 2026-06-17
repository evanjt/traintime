package com.evanjt.traintime.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DepartureTest {
    private fun dep(minutesUntil: Int) = Departure(
        destination = "Brig",
        minutesUntil = minutesUntil,
        departureTimestamp = 1000L,
        delay = 0,
        platform = "1",
        platformChanged = false,
        lineNumber = "IC8",
        category = "IC",
        trainNumber = null,
        operatorRef = null,
    )

    @Test
    fun `minutes text covers gone, now and minutes`() {
        assertEquals("gone", dep(-1).minutesText)
        assertEquals("now", dep(0).minutesText)
        assertEquals("5'", dep(5).minutesText)
    }

    @Test
    fun `is gone only when negative`() {
        assertTrue(dep(-1).isGone)
        assertFalse(dep(0).isGone)
        assertFalse(dep(3).isGone)
    }
}
