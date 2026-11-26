package com.evanjt.traintime.data.api

import com.evanjt.traintime.data.model.staleMinutes
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// Scenario: through an upstream outage the API serves a station's last list
// with `"stale": true` and the unix time it was fetched.
// Expected behaviour: the board keeps the rows and knows their age in whole
// minutes, at least one; a live list carries no age.
class StaleBoardTest {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }
    private val now = 1_790_000_000L

    private fun decode(body: String) = json.decodeFromString<DeparturesResponseDto>(body)

    @Test
    fun `a stale list keeps its fetch time`() {
        val dto = decode(
            """{"departures": [{"to": "Thun", "number": "IC61", "departure": ${now + 300}}],
               "stale": true, "fetchedAt": ${now - 1200}}""",
        )
        assertEquals(1, dto.departures.size)
        assertEquals(now - 1200, dto.staleSince)
        assertEquals(20, staleMinutes(dto.staleSince, now))
    }

    @Test
    fun `a live list has no age`() {
        val dto = decode("""{"departures": [], "fetchedAt": ${now - 1200}}""")
        assertNull(dto.staleSince)
        assertNull(staleMinutes(dto.staleSince, now))
    }

    @Test
    fun `a list under a minute old reads as one minute`() {
        assertEquals(1, staleMinutes(now - 20, now))
    }
}
