package com.evanjt.traintime.data.prefs

import com.evanjt.traintime.data.model.Favourite
import org.junit.Assert.assertEquals
import org.junit.Test

class FavouritesUnionTest {
    private fun fav(station: String, line: String, dest: String, name: String = station) =
        Favourite(stationId = station, stationName = name, lineNumber = line, destination = dest)

    @Test
    fun unionKeepsEveryDistinctFavourite() {
        val local = listOf(fav("8507000", "IC1", "Bern"))
        val remote = listOf(fav("8501120", "IR90", "Visp"))
        assertEquals(local + remote, FavouritesStore.union(local, remote))
    }

    @Test
    fun unionDedupesOnIdKeepingLocal() {
        val local = listOf(fav("8507000", "IC1", "Bern"))
        val remote = listOf(fav("8507000", "IC1", "Bern"), fav("8501120", "IR90", "Visp"))
        val merged = FavouritesStore.union(local, remote)
        assertEquals(2, merged.size)
        assertEquals(listOf("8507000:IC1:Bern", "8501120:IR90:Visp"), merged.map { it.id })
    }

    @Test
    fun unionDedupesDespiteStationNameDrift() {
        // Same id, different stationName: still one favourite (dedup on id, not ==).
        val local = listOf(fav("8507000", "IC1", "Bern", name = "Bern"))
        val remote = listOf(fav("8507000", "IC1", "Bern", name = "Bern Bahnhof"))
        val merged = FavouritesStore.union(local, remote)
        assertEquals(1, merged.size)
        assertEquals("Bern", merged.first().stationName)
    }

    @Test
    fun unionIsIdempotentAndOrderDeterministic() {
        val local = listOf(fav("a", "1", "x"), fav("b", "2", "y"))
        val remote = listOf(fav("b", "2", "y"), fav("c", "3", "z"))
        val once = FavouritesStore.union(local, remote)
        // Re-merging the result against either side yields the same list (the
        // convergence property the sync loop-guard relies on).
        assertEquals(once, FavouritesStore.union(once, remote))
        assertEquals(once, FavouritesStore.union(local, once))
        assertEquals(listOf("a:1:x", "b:2:y", "c:3:z"), once.map { it.id })
    }
}
