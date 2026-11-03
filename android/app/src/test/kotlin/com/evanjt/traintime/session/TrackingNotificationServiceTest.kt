package com.evanjt.traintime.session

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.evanjt.traintime.data.model.FocusedDeparture
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

// Scenario: the session ends while something still holds the card, a fetch in
// flight, a racing redraw, or a card left by an earlier instance.
// Expected behaviour: once the session has ended the card is gone and nothing
// can bring it back, and Stop clears it whichever instance receives it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TrackingNotificationServiceTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager = context.getSystemService(NotificationManager::class.java)

    private fun card(): Notification? = shadowOf(manager).getNotification(TrackingNotificationService.NOTIF_ID)

    private fun snapshot(secondsFromNow: Long) = TrackingSnapshot(
        focused = FocusedDeparture(
            destination = "Laupen BE",
            departureTimestamp = System.currentTimeMillis() / 1000 + secondsFromNow,
            lineNumber = "S2",
            category = "S",
            trainNumber = null,
            operatorRef = null,
            delay = 0,
            platform = "",
            platformChanged = false,
        ),
        stationId = null,
        stationName = "Bern",
        stationLat = null,
        stationLon = null,
        walkDistMeters = null,
        gpsOk = false,
    )

    @Before
    fun holdTheLoop() {
        // Foreground keeps the service's own loop from fetching or locating.
        TrackingSessionBus.appForeground.value = true
    }

    @After
    fun release() {
        TrackingSessionBus.appForeground.value = false
    }

    @Test
    fun `stop clears a card left by an earlier instance`() {
        manager.notify(
            TrackingNotificationService.NOTIF_ID,
            Notification.Builder(context, "live_tracking").setOngoing(true).build(),
        )
        Robolectric.buildService(
            TrackingNotificationService::class.java,
            Intent(context, TrackingNotificationService::class.java)
                .setAction(TrackingNotificationService.ACTION_STOP),
        ).create().startCommand(0, 1)
        assertNull(card())
    }

    @Test
    fun `a redraw after teardown posts nothing`() {
        val snap = snapshot(secondsFromNow = 3 * 60 * 60)
        val controller = Robolectric.buildService(
            TrackingNotificationService::class.java,
            TrackingNotificationService.startIntent(context, snap),
        ).create().startCommand(0, 1)
        assertNotNull(card())
        val service = controller.get()
        controller.destroy()
        service.pushNotification(snap)
        assertNull(card())
    }

    @Test
    fun `teardown clears the card`() {
        val controller = Robolectric.buildService(
            TrackingNotificationService::class.java,
            TrackingNotificationService.startIntent(context, snapshot(secondsFromNow = 3 * 60 * 60)),
        ).create().startCommand(0, 1)
        controller.destroy()
        assertNull(card())
    }

    @Test
    fun `a start for a train that has already left ends at once`() {
        val controller = Robolectric.buildService(
            TrackingNotificationService::class.java,
            TrackingNotificationService.startIntent(context, snapshot(secondsFromNow = -10 * 60)),
        ).create().startCommand(0, 1)
        assertTrue(shadowOf(controller.get()).isStoppedBySelf)
        assertNull(card())
        controller.destroy()
    }

    @Test
    fun `the start intent carries the session mutes`() {
        val snap = snapshot(secondsFromNow = 3 * 60 * 60).let {
            it.copy(mutes = SessionMutes(it.focused.departureTimestamp, sound = false, buzz = true))
        }
        val decoded = TrackingNotificationService.decodeSnapshot(TrackingNotificationService.startIntent(context, snap))
        assertEquals(snap.mutes, decoded?.mutes)
    }

    @Test
    fun `a redelivered start restores the session mutes`() {
        TrackingSessionBus.endSession(null)
        val snap = snapshot(secondsFromNow = 3 * 60 * 60).let {
            it.copy(mutes = SessionMutes(it.focused.departureTimestamp, sound = false))
        }
        val controller = Robolectric.buildService(
            TrackingNotificationService::class.java,
            TrackingNotificationService.startIntent(context, snap),
        ).create().startCommand(0, 1)
        assertEquals(false, TrackingSessionBus.mutesFor(snap.focused.departureTimestamp).sound)
        controller.destroy()
        assertNull(TrackingSessionBus.mutesFor(snap.focused.departureTimestamp).sound)
    }
}
