package com.evanjt.traintime.session

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionMuteTest {
    private val dep = 1_800_000_000L

    @After
    fun reset() {
        TrackingSessionBus.endSession(null)
    }

    @Test
    fun follows_settings_without_a_session_choice() {
        assertEquals(MuteLook.ON, SessionMute.look(global = true, session = null))
        assertEquals(MuteLook.OFF, SessionMute.look(global = false, session = null))
        assertTrue(SessionMute.effective(global = true, session = null))
        assertFalse(SessionMute.effective(global = false, session = null))
    }

    @Test
    fun a_session_mute_overrides_settings_on() {
        assertFalse(SessionMute.effective(global = true, session = false))
        assertEquals(MuteLook.MUTED_THIS_TRIP, SessionMute.look(global = true, session = false))
    }

    @Test
    fun a_session_unmute_overrides_settings_off() {
        assertTrue(SessionMute.effective(global = false, session = true))
        assertEquals(MuteLook.ON, SessionMute.look(global = false, session = true))
    }

    @Test
    fun tap_flips_this_trip_and_lands_back_on_settings() {
        assertEquals(false, SessionMute.tapped(global = true, session = null))
        assertNull(SessionMute.tapped(global = true, session = false))
        assertEquals(true, SessionMute.tapped(global = false, session = null))
        assertNull(SessionMute.tapped(global = false, session = true))
    }

    // A hold turns it off for every trip unless it already shows off in
    // Settings. The trip's override is dropped, so the row then shows Settings.
    @Test
    fun hold_turns_it_off_for_every_trip_unless_settings_already_has_it_off() {
        val rows = listOf(
            Triple(true, null, false),
            Triple(true, false, false),
            Triple(false, true, false),
            Triple(false, null, true),
        )
        for ((global, session, expected) in rows) {
            val held = SessionMute.held(global, session)
            assertEquals("global=$global session=$session", expected, held)
            val shown = if (expected) MuteLook.ON else MuteLook.OFF
            assertEquals("global=$global session=$session", shown, SessionMute.look(held, session = null))
        }
    }

    @Test
    fun the_sound_mute_picks_the_quiet_alert_channel() {
        assertEquals(com.evanjt.traintime.notify.AlertChannels.TRACKING_QUIET, SessionMute.alertChannel(global = true, session = false))
        assertEquals(com.evanjt.traintime.notify.AlertChannels.TRACKING, SessionMute.alertChannel(global = false, session = true))
        assertEquals(com.evanjt.traintime.notify.AlertChannels.TRACKING, SessionMute.alertChannel(global = true, session = null))
    }

    @Test
    fun the_buzz_mute_gates_in_app_haptics_only_while_tracking() {
        val muted = SessionMutes(dep, sound = null, buzz = false)
        assertFalse(SessionMute.hapticsOn(global = true, mutes = muted, trackingDepTs = dep))
        assertTrue(SessionMute.hapticsOn(global = true, mutes = muted, trackingDepTs = null))
        assertTrue(SessionMute.hapticsOn(global = false, mutes = SessionMutes(dep, buzz = true), trackingDepTs = dep))
    }

    @Test
    fun the_mute_ends_with_the_session() {
        TrackingSessionBus.beginSession(dep)
        TrackingSessionBus.setSound(dep, false)
        TrackingSessionBus.endSession(dep)
        assertNull(TrackingSessionBus.mutesFor(dep).sound)
    }

    @Test
    fun a_new_departure_starts_with_no_mutes() {
        TrackingSessionBus.beginSession(dep)
        TrackingSessionBus.setBuzz(dep, false)
        TrackingSessionBus.beginSession(dep + 600)
        assertNull(TrackingSessionBus.mutesFor(dep + 600).buzz)
    }

    @Test
    fun reopening_the_same_session_keeps_its_mutes() {
        TrackingSessionBus.beginSession(dep)
        TrackingSessionBus.setSound(dep, false)
        TrackingSessionBus.beginSession(dep)
        assertEquals(false, TrackingSessionBus.mutesFor(dep).sound)
    }

    @Test
    fun ending_another_session_leaves_these_mutes() {
        TrackingSessionBus.beginSession(dep)
        TrackingSessionBus.setSound(dep, false)
        TrackingSessionBus.endSession(dep - 600)
        assertEquals(false, TrackingSessionBus.mutesFor(dep).sound)
    }
}
