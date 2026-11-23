package com.evanjt.traintime.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

// Scenario: a board fetched before a pause is shown again minutes later.
// Expected behaviour: its rows count down to the clock, so a train that left
// meanwhile reads gone and can't be tracked.
class DepartureAgeTest {
    private val fetchedAt = 1_800_000_000L

    private fun dep(departsInSec: Long, delay: Int = 0) = Departure(
        destination = "Brig",
        minutesUntil = (departsInSec / 60).toInt(),
        departureTimestamp = fetchedAt + departsInSec,
        delay = delay,
        platform = "1",
        platformChanged = false,
        lineNumber = "IC8",
        category = "IC",
        trainNumber = null,
        operatorRef = null,
    )

    @Test
    fun `a train two minutes out is gone five minutes later`() {
        val aged = dep(120).at(fetchedAt + 300)
        assertEquals(-3, aged.minutesUntil)
        assertTrue(aged.isGone)
        assertFalse(aged.isSelectable)
    }

    @Test
    fun `a delayed train is still selectable while its delay covers the pause`() {
        val aged = dep(120, delay = 5).at(fetchedAt + 300)
        assertFalse(aged.isGone)
        assertTrue(aged.isSelectable)
    }

    @Test
    fun `aging within the same minute keeps the row itself`() {
        val row = dep(630)
        assertSame(row, row.at(fetchedAt + 20))
    }

    @Test
    fun `a row without a timestamp is left alone`() {
        val row = dep(600).copy(departureTimestamp = null)
        assertSame(row, row.at(fetchedAt + 3600))
    }

    @Test
    fun `aging a board keeps the list when nothing changed`() {
        val board = listOf(dep(630), dep(930))
        assertSame(board, board.at(fetchedAt + 10))
        assertEquals(listOf(9, 14), board.at(fetchedAt + 70).map { it.minutesUntil })
    }
}
