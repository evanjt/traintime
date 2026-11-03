package com.evanjt.traintime.ui.tracking

import com.evanjt.traintime.R
import com.evanjt.traintime.session.MuteLook
import com.evanjt.traintime.session.SessionMute
import org.junit.Assert.assertEquals
import org.junit.Test

// The second caption under Sound and Buzz states the Settings value, which the
// look alone can't carry: on for this trip reads the same whether Settings is
// on or off.
class MuteCaptionTest {
    @Test
    fun off_in_settings_reads_usually_off() {
        val state = SessionMute.state(global = false, session = null)
        assertEquals(MuteLook.OFF, state.look)
        assertEquals(R.string.trip_usually_off, usualCaption(state))
    }

    @Test
    fun muted_for_this_trip_reads_usually_on() {
        val state = SessionMute.state(global = true, session = false)
        assertEquals(MuteLook.MUTED_THIS_TRIP, state.look)
        assertEquals(R.string.trip_usually_on, usualCaption(state))
    }

    @Test
    fun on_follows_settings() {
        assertEquals(R.string.trip_usually_on, usualCaption(SessionMute.state(global = true, session = null)))
    }

    @Test
    fun on_for_this_trip_over_settings_off_reads_usually_off() {
        val state = SessionMute.state(global = false, session = true)
        assertEquals(MuteLook.ON, state.look)
        assertEquals(R.string.trip_usually_off, usualCaption(state))
    }
}
