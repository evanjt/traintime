package com.evanjt.traintime.widget

import com.evanjt.traintime.data.model.TransportMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetLogicTest {
    private val now = 1_718_000_000L

    private fun dep(line: String, dest: String, inSeconds: Long) = WidgetDeparture(
        destination = dest,
        departureTimestamp = now + inSeconds,
        delay = 0,
        platform = "1",
        platformChanged = false,
        lineNumber = line,
    )

    private fun station(id: String, vararg deps: WidgetDeparture) =
        WidgetStation(id = id, name = id, departures = deps.toList())

    @Test
    fun `minutes until covers gone, now and future`() {
        assertTrue(dep("IC8", "Brig", -90).isGone(now))
        assertEquals(0, dep("IC8", "Brig", 30).minutesUntil(now))
        assertEquals(10, dep("IC8", "Brig", 600).minutesUntil(now))
    }

    @Test
    fun `favourites block takes one not-gone departure per key, time-ordered`() {
        val deps = listOf(
            dep("IR90", "Genève", 300),
            dep("IC8", "Brig", -60), // gone, skipped
            dep("IC8", "Brig", 120), // first live match for IC8|Brig
            dep("IC8", "Brig", 600), // duplicate key, skipped
        )
        val block = WidgetFavourites.block(deps, setOf("IC8|Brig", "IR90|Genève"), now)
        assertEquals(listOf("IC8", "IR90"), block.map { it.lineNumber })
    }

    @Test
    fun `favourites block is empty without keys`() {
        assertTrue(WidgetFavourites.block(listOf(dep("IC8", "Brig", 120)), emptySet(), now).isEmpty())
    }

    @Test
    fun `available modes lists only non-empty groups`() {
        val r = WidgetFetchResult(train = listOf(station("a")), tram = listOf(station("b")))
        assertEquals(listOf(TransportMode.TRAIN, TransportMode.TRAM), r.availableModes)
    }

    @Test
    fun `current station clamps an out-of-range index`() {
        val r = WidgetFetchResult(train = listOf(station("a"), station("b")), selectedStationIndex = 5)
        assertEquals("b", r.currentStation?.id)
    }

    @Test
    fun `current station is null when the selected mode is empty`() {
        assertNull(WidgetFetchResult(bus = listOf(station("a"))).currentStation)
    }

    @Test
    fun `is refreshing only within the 15s window`() {
        assertTrue(WidgetState(refreshStartedAt = now).isRefreshing(now + 5))
        assertFalse(WidgetState(refreshStartedAt = now).isRefreshing(now + 20))
        assertFalse(WidgetState(refreshStartedAt = 0).isRefreshing(now))
    }
}
