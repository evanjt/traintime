package com.evanjt.traintime.data.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

// Guards the persisted JSON shape: a field rename or type change would break
// stored favourites / pinned stations across an app update.
class SerializationTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `pinned station round-trips`() {
        val list = listOf(
            PinnedStation("8500074", "Sion", 46.23, 7.36),
            PinnedStation("8501120", "Lausanne", null, null),
        )
        assertEquals(list, json.decodeFromString<List<PinnedStation>>(json.encodeToString(list)))
    }

    @Test
    fun `favourite round-trips`() {
        val list = listOf(Favourite("8500074", "Sion", "IR95", "Genève"))
        assertEquals(list, json.decodeFromString<List<Favourite>>(json.encodeToString(list)))
    }
}
