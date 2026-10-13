package com.evanjt.traintime.data.model

import com.evanjt.traintime.data.api.DepartureDto
import com.evanjt.traintime.domain.TrackingLogic
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// Scenario: the API sends the timetabled time plus a delay in minutes. A late
// bus is still on its way after its scheduled minute has passed.
// Expected behaviour: a departure is gone only once its effective time
// (schedule + delay) has passed, on the board and in the tracking countdown.
class LateDepartureTest {
    private val now = 1_790_000_000L

    private fun board(secondsFromNow: Long, delay: Int?) =
        DepartureDto(to = "Bern Bahnhof", category = "B", number = "10", departure = now + secondsFromNow, delay = delay)
            .toDeparture(now)

    private fun focused(secondsFromNow: Long, delay: Int) = FocusedDeparture(
        destination = "Bern Bahnhof",
        departureTimestamp = now + secondsFromNow,
        lineNumber = "10",
        category = "B",
        trainNumber = null,
        operatorRef = null,
        delay = delay,
        platform = "",
        platformChanged = false,
    )

    @Test
    fun `on-time departure keeps the existing gone threshold`() {
        assertFalse(board(secondsFromNow = -30, delay = 0).isGone)
        assertTrue(board(secondsFromNow = -61, delay = 0).isGone)
        assertTrue(board(secondsFromNow = -300, delay = null).isGone)
    }

    @Test
    fun `late bus is not gone just after its scheduled minute`() {
        assertFalse(board(secondsFromNow = -61, delay = 4).isGone)
        assertFalse(board(secondsFromNow = -120, delay = 4).isGone)
    }

    @Test
    fun `late bus is not gone until its effective time has passed`() {
        assertFalse(board(secondsFromNow = -4 * 60L, delay = 4).isGone)
        assertFalse(board(secondsFromNow = -4 * 60L - 30, delay = 4).isGone)
        assertTrue(board(secondsFromNow = -4 * 60L - 61, delay = 4).isGone)
    }

    @Test
    fun `heavily delayed bus stays on the board`() {
        assertFalse(board(secondsFromNow = -15 * 60L, delay = 20).isGone)
        assertTrue(board(secondsFromNow = -22 * 60L, delay = 20).isGone)
    }

    @Test
    fun `late bus is still selectable for tracking from the board`() {
        val late = board(secondsFromNow = -90, delay = 3)
        assertFalse(late.isGone)
        assertEquals(3, late.delay)
    }

    @Test
    fun `negative delay from the wire is treated as on time`() {
        assertTrue(board(secondsFromNow = -61, delay = -2).isGone)
    }

    @Test
    fun `tracking countdown does not say departed while the late bus is still coming`() {
        assertNotEquals("Departed", focused(secondsFromNow = -60, delay = 4).countdownText(now))
        assertNotEquals("Departed", focused(secondsFromNow = -3 * 60L, delay = 4).countdownText(now))
    }

    @Test
    fun `tracking countdown says departed once the effective time has passed`() {
        assertEquals("Departed", focused(secondsFromNow = -60, delay = 0).countdownText(now))
        assertEquals("Departed", focused(secondsFromNow = -5 * 60L, delay = 4).countdownText(now))
    }

    // Observed live: the board row of a +4 train is still delivered two minutes
    // after its scheduled time, yet matching dropped it and tracking exited.
    @Test
    fun `late train still on the board keeps matching the tracked departure`() {
        val row = board(secondsFromNow = -130, delay = 4)
        val tracked = focused(secondsFromNow = -130, delay = 4)
        assertNotNull(TrackingLogic.matchFocused(listOf(row), tracked, now))
    }
}
