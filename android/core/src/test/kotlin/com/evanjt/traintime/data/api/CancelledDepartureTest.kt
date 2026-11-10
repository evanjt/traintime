package com.evanjt.traintime.data.api

import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.domain.TrackingLogic
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Scenario: the API marks a departure row `"cancelled": true` and omits the
// field otherwise.
// Expected behaviour: the row decodes as cancelled, stays on the board, and is
// never picked for tracking, a reminder or the next departure.
class CancelledDepartureTest {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }
    private val now = 1_790_000_000L

    private val body = """
        {"departures": [
          {"to": "Thun", "category": "IC", "number": "IC61", "departure": ${now + 300}, "platform": "4", "cancelled": true},
          {"to": "Thun", "category": "IC", "number": "IC61", "departure": ${now + 1800}, "platform": "4"}
        ]}
    """.trimIndent()

    private fun rows() = json.decodeFromString<DeparturesResponseDto>(body).departures.map { it.toDeparture(now) }

    @Test
    fun `a row flagged cancelled decodes as cancelled`() {
        val (cancelled, running) = rows()
        assertTrue(cancelled.cancelled)
        assertFalse(running.cancelled)
    }

    @Test
    fun `a cancelled row is not selectable even before it would leave`() {
        val (cancelled, running) = rows()
        assertFalse(cancelled.isGone)
        assertFalse(cancelled.isSelectable)
        assertTrue(running.isSelectable)
    }

    @Test
    fun `the next selectable departure skips the cancelled train`() {
        assertEquals(now + 1800, rows().first { it.isSelectable }.departureTimestamp)
    }

    @Test
    fun `a tracked train that is cancelled still matches its own row`() {
        val tracked = FocusedDeparture(
            destination = "Thun",
            departureTimestamp = now + 300,
            lineNumber = "IC61",
            category = "IC",
            trainNumber = null,
            operatorRef = null,
            delay = 0,
            platform = "4",
            platformChanged = false,
        )
        val best = TrackingLogic.matchFocused(rows(), tracked, now)
        assertEquals(now + 300, best?.departureTimestamp)
    }
}
