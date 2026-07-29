package com.evanjt.traintime.session

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.ui.TrackingStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackingLogicTest {
    private val now = 1_800_000_000L

    private fun focused(dep: Long = now + 600, delay: Int = 0, train: String? = "1820") = FocusedDeparture(
        destination = "Bern",
        departureTimestamp = dep,
        lineNumber = "IC1",
        category = "IC",
        trainNumber = train,
        operatorRef = null,
        delay = delay,
        platform = "7",
        platformChanged = false,
    )

    private fun row(
        dest: String = "Bern",
        minutes: Int = 10,
        dep: Long? = now + 600,
        delay: Int = 0,
        platform: String = "7",
        platformChanged: Boolean = false,
        train: String? = "1820",
    ) = Departure(
        destination = dest,
        minutesUntil = minutes,
        departureTimestamp = dep,
        delay = delay,
        platform = platform,
        platformChanged = platformChanged,
        lineNumber = "IC1",
        category = "IC",
        trainNumber = train,
        operatorRef = null,
    )

    @Test
    fun matches_by_destination() {
        val best = TrackingLogic.matchFocused(listOf(row(), row(dest = "Chur", train = "99")), focused(), now)
        assertEquals("Bern", best?.destination)
    }

    @Test
    fun matches_by_train_number_when_destination_differs() {
        // A protected route leg carries the alight stop, not the terminus.
        val best = TrackingLogic.matchFocused(listOf(row(dest = "Genève-Aéroport")), focused(), now)
        assertEquals("1820", best?.trainNumber)
    }

    @Test
    fun ignores_rows_departed_over_a_minute_ago() {
        assertNull(TrackingLogic.matchFocused(listOf(row(minutes = -2)), focused(), now))
    }

    @Test
    fun picks_the_row_closest_to_the_focused_departure() {
        val later = row(minutes = 40, dep = now + 2400, train = "1822")
        val target = row(minutes = 10)
        val best = TrackingLogic.matchFocused(listOf(later, target), focused(), now)
        assertEquals(target, best)
    }

    @Test
    fun adopt_takes_platform_terminus_and_delay() {
        val adopted = TrackingLogic.adopt(
            focused(),
            row(dest = "Bern Wankdorf", delay = 3, platform = "9", platformChanged = true),
        )
        assertEquals("9", adopted.platform)
        assertTrue(adopted.platformChanged)
        assertEquals("Bern Wankdorf", adopted.destination)
        assertEquals(3, adopted.delay)
    }

    @Test
    fun adopt_keeps_platform_when_board_row_has_none() {
        val adopted = TrackingLogic.adopt(focused(), row(platform = ""))
        assertEquals("7", adopted.platform)
    }

    @Test
    fun buffers_subtract_walk_and_add_delay() {
        // 10 min to departure, 4 min walk, +2 delay.
        val f = focused(delay = 2)
        assertEquals(6.0, TrackingLogic.scheduledBuffer(f, 4.0, now), 0.01)
        assertEquals(8.0, TrackingLogic.effectiveBuffer(f, 4.0, now), 0.01)
    }

    @Test
    fun status_maps_buffer_to_verdict() {
        assertEquals(TrackingStatus.AHEAD, TrackingLogic.status(3.0, gpsOk = true))
        assertEquals(TrackingStatus.BEHIND, TrackingLogic.status(-3.0, gpsOk = true))
        assertEquals(TrackingStatus.ON_TIME, TrackingLogic.status(0.2, gpsOk = true))
        assertEquals(TrackingStatus.NO_GPS, TrackingLogic.status(3.0, gpsOk = false))
    }

    @Test
    fun departed_needs_the_grace_to_pass() {
        assertFalse(TrackingLogic.departed(focused(dep = now - 60), now))
        assertTrue(TrackingLogic.departed(focused(dep = now - 120), now))
    }

    @Test
    fun bar_comfortable_margin_paints_green_from_centre() {
        // +1.5 sched, +3 effect: dark green 500..750, light green 750..1000.
        val bar = TrackingLogic.barModel(1.5, 3.0, gpsOk = true)
        assertEquals(
            listOf(
                BarRun(500, BarZone.TRACK),
                BarRun(250, BarZone.DARK_GREEN),
                BarRun(250, BarZone.LIGHT_GREEN),
            ),
            bar.runs,
        )
        assertEquals(1000, bar.position)
    }

    @Test
    fun bar_irrecoverable_paints_red_up_to_centre() {
        // -3 sched, -1.5 effect: amber 0..250 (delay clawed back), red 250..500.
        val bar = TrackingLogic.barModel(-3.0, -1.5, gpsOk = true)
        assertEquals(
            listOf(
                BarRun(250, BarZone.AMBER),
                BarRun(250, BarZone.DARK_RED),
                BarRun(500, BarZone.TRACK),
            ),
            bar.runs,
        )
        assertEquals(250, bar.position)
    }

    @Test
    fun bar_delay_rescue_straddles_the_centre() {
        // -1.5 sched, +1.5 effect: amber left of centre, light green right.
        val bar = TrackingLogic.barModel(-1.5, 1.5, gpsOk = true)
        assertEquals(
            listOf(
                BarRun(250, BarZone.TRACK),
                BarRun(250, BarZone.AMBER),
                BarRun(250, BarZone.LIGHT_GREEN),
                BarRun(250, BarZone.TRACK),
            ),
            bar.runs,
        )
        assertEquals(750, bar.position)
    }

    @Test
    fun bar_without_gps_is_all_grey() {
        val bar = TrackingLogic.barModel(2.0, 2.0, gpsOk = false)
        assertEquals(listOf(BarRun(1000, BarZone.GREY)), bar.runs)
        assertEquals(1000, bar.position)
    }

    @Test
    fun bar_clamps_beyond_scale_and_drops_degenerate_runs() {
        // Huge margins clamp to the edge; zero-length light green vanishes.
        val bar = TrackingLogic.barModel(10.0, 10.0, gpsOk = true)
        assertEquals(
            listOf(BarRun(500, BarZone.TRACK), BarRun(500, BarZone.DARK_GREEN)),
            bar.runs,
        )
        assertEquals(1000, bar.position)
        assertEquals(1000, bar.runs.sumOf { it.length })
    }
}
