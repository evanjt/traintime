package com.evanjt.traintime.data.prefs

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Favourite
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FavouritesLogicTest {
    private fun departure(line: String, dest: String, ts: Long) = Departure(
        destination = dest,
        minutesUntil = 5,
        departureTimestamp = ts,
        delay = 0,
        platform = "1",
        platformChanged = false,
        lineNumber = line,
        category = "IC",
        trainNumber = null,
        operatorRef = null,
    )

    private val favIc8 = Favourite("8501120", "Lausanne", "IC8", "Brig")
    private val favIr90 = Favourite("8501120", "Lausanne", "IR90", "Genève")

    @Test
    fun `extract returns first match per favourite sorted by time`() {
        val departures = listOf(
            departure("IR90", "Genève", 2000),
            departure("IC8", "Brig", 1000),
            departure("IC8", "Brig", 3000),
            departure("S3", "Villeneuve", 500),
        )

        val extracted = FavouritesStore.extract(listOf(favIc8, favIr90), departures)

        assertEquals(2, extracted.size)
        assertEquals(1000L, extracted[0].departureTimestamp)
        assertEquals("IC8", extracted[0].lineNumber)
        assertEquals(2000L, extracted[1].departureTimestamp)
    }

    @Test
    fun `extract with no favourites is empty`() {
        assertEquals(emptyList<Departure>(), FavouritesStore.extract(emptyList(), listOf(departure("IC8", "Brig", 1000))))
    }

    @Test
    fun `param formats line colon destination pairs`() {
        assertEquals("IC8:Brig,IR90:Genève", FavouritesStore.param(listOf(favIc8, favIr90)))
        assertNull(FavouritesStore.param(emptyList()))
    }

    @Test
    fun `merge keeps regular list when favourites already present`() {
        val regular = listOf(departure("IC8", "Brig", 1000), departure("S3", "Villeneuve", 1500))
        val favourites = listOf(departure("IC8", "Brig", 1000))

        val merged = FavouritesStore.merge(favourites, regular)

        assertEquals(2, merged.size)
    }

    @Test
    fun `merge inserts missing favourites in time order`() {
        val regular = listOf(departure("S3", "Villeneuve", 1500))
        val favourites = listOf(departure("IC8", "Brig", 1000))

        val merged = FavouritesStore.merge(favourites, regular)

        assertEquals(listOf("IC8", "S3"), merged.map { it.lineNumber })
    }
}
