package ch.traintime.shared

import ch.traintime.shared.models.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ModelsTest {
    @Test
    fun `TransportMode from icon string`() {
        assertEquals(TransportMode.BUS, TransportMode.from("bus"))
        assertEquals(TransportMode.TRAM, TransportMode.from("tram"))
        assertEquals(TransportMode.SPECIAL, TransportMode.from("special"))
        assertEquals(TransportMode.TRAIN, TransportMode.from(null))
        assertEquals(TransportMode.TRAIN, TransportMode.from("unknown"))
    }

    @Test
    fun `Departure minutesText formatting`() {
        val gone = Departure(destination = "A", minutesUntil = -1, departureTimestamp = null, delay = 0, platform = "", platformChanged = false, lineNumber = "")
        assertEquals("gone", gone.minutesText)

        val now = Departure(destination = "B", minutesUntil = 0, departureTimestamp = null, delay = 0, platform = "", platformChanged = false, lineNumber = "")
        assertEquals("now", now.minutesText)

        val five = Departure(destination = "C", minutesUntil = 5, departureTimestamp = null, delay = 0, platform = "", platformChanged = false, lineNumber = "")
        assertEquals("5'", five.minutesText)
    }

    @Test
    fun `Departure isGone`() {
        val gone = Departure(destination = "A", minutesUntil = -1, departureTimestamp = null, delay = 0, platform = "", platformChanged = false, lineNumber = "")
        assertTrue(gone.isGone)

        val notGone = Departure(destination = "B", minutesUntil = 0, departureTimestamp = null, delay = 0, platform = "", platformChanged = false, lineNumber = "")
        assertFalse(notGone.isGone)
    }

    @Test
    fun `FocusedDeparture countdownText`() {
        val now = (System.currentTimeMillis() / 1000).toInt()

        val departed = FocusedDeparture("A", now - 60, 0, "", false)
        assertEquals("Departed", departed.countdownText)

        val imminent = FocusedDeparture("B", now + 3, 0, "", false)
        assertEquals("now", imminent.countdownText)

        val soon = FocusedDeparture("C", now + 90, 0, "", false)
        assertTrue(soon.countdownText.contains(":"))

        val later = FocusedDeparture("D", now + 600, 0, "", false)
        assertTrue(later.countdownText.contains("min"))
    }

    @Test
    fun `GPSQuality from accuracy`() {
        assertEquals(GPSQuality.UNAVAILABLE, GPSQuality.from(null))
        assertEquals(GPSQuality.UNAVAILABLE, GPSQuality.from(-1f))
        assertEquals(GPSQuality.GOOD, GPSQuality.from(10f))
        assertEquals(GPSQuality.POOR, GPSQuality.from(50f))
        assertEquals(GPSQuality.POOR, GPSQuality.from(150f))
    }
}
