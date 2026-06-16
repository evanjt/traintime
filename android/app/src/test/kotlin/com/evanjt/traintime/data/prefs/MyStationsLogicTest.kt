package com.evanjt.traintime.data.prefs

import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import org.junit.Assert.assertEquals
import org.junit.Test

class MyStationsLogicTest {
    private fun station(id: String) =
        Station(id = id, name = id, lat = null, lon = null, mode = TransportMode.TRAIN)

    // API returns nearby stations in distance order (nearest first).
    private val nearby = listOf(station("near"), station("big"), station("far"))

    @Test
    fun `reorder with no pins keeps distance order`() {
        assertEquals(
            listOf("near", "big", "far"),
            MyStationsStore.reorder(nearby, emptySet()).map { it.id },
        )
    }

    @Test
    fun `reorder bubbles a pinned station to the front`() {
        assertEquals(
            listOf("big", "near", "far"),
            MyStationsStore.reorder(nearby, setOf("big")).map { it.id },
        )
    }

    @Test
    fun `reorder ignores pins not in the nearby list`() {
        assertEquals(
            listOf("near", "big", "far"),
            MyStationsStore.reorder(nearby, setOf("zurich")).map { it.id },
        )
    }

    @Test
    fun `reorder preserves distance order within the pinned and unpinned groups`() {
        // near + far pinned: pinned-first in their original order, then the rest.
        assertEquals(
            listOf("near", "far", "big"),
            MyStationsStore.reorder(nearby, setOf("near", "far")).map { it.id },
        )
    }
}
