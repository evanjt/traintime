package com.evanjt.traintime.notify

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AlertChannelsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager = context.getSystemService(NotificationManager::class.java)

    @Test
    fun `alert sounds on picks the original channels`() {
        assertEquals(AlertChannels.TRACKING, AlertChannels.forAlert(sounds = true))
        assertEquals(AlertChannels.REMINDER, AlertChannels.forReminder(sounds = true))
    }

    @Test
    fun `alert sounds off picks the quiet twins`() {
        assertEquals(AlertChannels.TRACKING_QUIET, AlertChannels.forAlert(sounds = false))
        assertEquals(AlertChannels.REMINDER_QUIET, AlertChannels.forReminder(sounds = false))
    }

    @Test
    fun `each twin is silent, vibrates and pops up like its original`() = runTest {
        AlertChannels.ensure(context)
        val pairs = listOf(
            AlertChannels.TRACKING to AlertChannels.TRACKING_QUIET,
            AlertChannels.REMINDER to AlertChannels.REMINDER_QUIET,
        )
        for ((originalId, twinId) in pairs) {
            val original = manager.getNotificationChannel(originalId)
            assertNotNull(originalId, original)
            val twin = manager.getNotificationChannel(twinId)
            assertNotNull(twinId, twin)
            assertNotEquals(originalId, twinId)
            assertNull(twinId, twin.sound)
            assertTrue(twinId, twin.shouldVibrate())
            assertNotNull(twinId, twin.vibrationPattern)
            assertEquals(twinId, original.importance, twin.importance)
            assertEquals(twinId, NotificationManager.IMPORTANCE_HIGH, twin.importance)
            assertNotNull(originalId, original.sound)
        }
    }
}
