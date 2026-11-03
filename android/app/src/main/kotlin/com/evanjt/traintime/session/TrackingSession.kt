package com.evanjt.traintime.session

import com.evanjt.traintime.data.model.FocusedDeparture
import kotlinx.coroutines.flow.MutableSharedFlow
import com.evanjt.traintime.notify.AlertChannels
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

// Everything the tracking notification renders. Built by the ViewModel while
// the app is foreground (its 10 s fetch is fresher) and by the service's own
// loop while backgrounded, so both paths feed one renderer.
data class TrackingSnapshot(
    val focused: FocusedDeparture,
    val stationId: String?,
    val stationName: String?,
    val stationLat: Double?,
    val stationLon: Double?,
    val walkDistMeters: Double?,
    val gpsOk: Boolean,
    val mutes: SessionMutes = SessionMutes(),
)

// This trip's choices for Sound and Buzz, keyed to the departure they were made
// for so they can't leak into the next session. null follows Settings, true or
// false overrides it until the session ends.
data class SessionMutes(
    val departureTimestamp: Long? = null,
    val sound: Boolean? = null,
    val buzz: Boolean? = null,
)

enum class MuteLook { ON, MUTED_THIS_TRIP, OFF }

// What a Sound or Buzz button shows: the trip's look and the Settings value a
// hold would flip, since on for this trip reads the same over either.
data class MuteState(val look: MuteLook, val usuallyOn: Boolean)

// The tracking screen's Sound and Buzz rules: tap decides for this trip, hold
// for always. Sound only picks the trip's alert channel and Buzz only gates the
// in-app haptics, so the alerts' own vibration stays with the phone's profile.
object SessionMute {
    fun effective(global: Boolean, session: Boolean?): Boolean = session ?: global

    fun look(global: Boolean, session: Boolean?): MuteLook = when {
        effective(global, session) -> MuteLook.ON
        global -> MuteLook.MUTED_THIS_TRIP
        else -> MuteLook.OFF
    }

    fun state(global: Boolean, session: Boolean?): MuteState = MuteState(look(global, session), global)

    // A tap flips what plays now. Landing on what Settings says drops the
    // override, so a second tap undoes the first.
    fun tapped(global: Boolean, session: Boolean?): Boolean? {
        val next = !effective(global, session)
        return if (next == global) null else next
    }

    // The new Settings value after a hold: off for every trip, unless it already
    // shows off in Settings. The trip's override is dropped with it.
    fun held(global: Boolean, session: Boolean?): Boolean = look(global, session) == MuteLook.OFF

    fun alertChannel(global: Boolean, session: Boolean?): String = AlertChannels.forAlert(effective(global, session))

    fun hapticsOn(global: Boolean, mutes: SessionMutes, trackingDepTs: Long?): Boolean {
        val session = mutes.buzz.takeIf { trackingDepTs != null && mutes.departureTimestamp == trackingDepTs }
        return effective(global, session)
    }
}

// Process-local link between MainViewModel and TrackingNotificationService.
// Both live in this process, so flows beat intents for everything except the
// service's own start/stop lifecycle.
object TrackingSessionBus {
    // Set from the VM's onAppear/onDisappear. The service's loop stays idle
    // while the app is foreground (the VM fetches and pushes instead), and
    // takes over the moment this drops to false.
    val appForeground = MutableStateFlow(false)

    // VM -> service: freshest snapshot to render while foreground.
    val vmPush = MutableSharedFlow<TrackingSnapshot>(extraBufferCapacity = 1)

    // Service -> VM: the notification's "Stop tracking" action. The VM exits
    // tracking so a reopened app doesn't resurrect the session.
    val stopRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    // The one owner of this trip's Sound and Buzz choices. The screen writes
    // it, the service reads it at alert time, and the snapshot carries it
    // through the redelivered start intent so a process death keeps them.
    val mutes = MutableStateFlow(SessionMutes())

    fun mutesFor(departureTimestamp: Long?): SessionMutes = mutes.value.scopedTo(departureTimestamp)

    private fun SessionMutes.scopedTo(departureTimestamp: Long?): SessionMutes =
        takeIf { departureTimestamp != null && it.departureTimestamp == departureTimestamp }
            ?: SessionMutes(departureTimestamp)

    // Reopening the same departure keeps its choices, any other starts clean.
    fun beginSession(departureTimestamp: Long) {
        mutes.update { if (it.departureTimestamp == departureTimestamp) it else SessionMutes(departureTimestamp) }
    }

    // null ends whatever session holds them.
    fun endSession(departureTimestamp: Long?) {
        mutes.update { if (departureTimestamp == null || it.departureTimestamp == departureTimestamp) SessionMutes() else it }
    }

    fun restore(restored: SessionMutes) {
        if (restored.departureTimestamp != null) mutes.value = restored
    }

    fun setSound(departureTimestamp: Long, sound: Boolean?) {
        mutes.update { it.scopedTo(departureTimestamp).copy(sound = sound) }
    }

    fun setBuzz(departureTimestamp: Long, buzz: Boolean?) {
        mutes.update { it.scopedTo(departureTimestamp).copy(buzz = buzz) }
    }
}
