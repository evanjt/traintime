package com.evanjt.traintime.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.PendingRouteLogic
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first

// Schedules the "your train leaves soon" heads-up for a queued shared route.
// WorkManager rather than an exact alarm: it persists across process death
// and reboot, and inexact timing is fine for a 15-minute lead.
object PendingRouteNotifier {
    const val CHANNEL_ID = "pending_route"
    const val NOTIF_ID = 2
    private const val WORK_NAME = "pending-route-notify"

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Saved route reminders",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    suspend fun schedule(context: Context, route: PendingRoute, nowEpochSeconds: Long) {
        val prefs = AppPrefs(context)
        val savedLead = prefs.routeReminderLeadMinutes.first() * 60L
        val connectionLead = prefs.connectionReminderLeadMinutes.first() * 60L
        val distance = userDistanceMeters(prefs, route)
        val notifyTs = PendingRouteLogic.notifyTs(route, savedLead, connectionLead, distance)
            ?: return cancel(context)
        val delay = notifyTs - nowEpochSeconds
        if (delay <= 0) return cancel(context) // already inside the window
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<PendingRouteNotifyWorker>()
                .setInitialDelay(delay, TimeUnit.SECONDS)
                .build(),
        )
    }

    // Absolute epoch-second the reminder is set to fire for this route, using
    // the same rule as schedule (distance-aware or static). For the in-app
    // "notified in X min" readout. Null when the route has no viable leg.
    suspend fun nextNotifyTs(context: Context, route: PendingRoute): Long? {
        val prefs = AppPrefs(context)
        val savedLead = prefs.routeReminderLeadMinutes.first() * 60L
        val connectionLead = prefs.connectionReminderLeadMinutes.first() * 60L
        return PendingRouteLogic.notifyTs(route, savedLead, connectionLead, userDistanceMeters(prefs, route))
    }

    // Straight-line distance from the last known location to the current leg's
    // origin, only in distance-aware mode. Null (static lead) when the feature
    // is off, no leg, or no stored coordinate.
    private suspend fun userDistanceMeters(prefs: AppPrefs, route: PendingRoute): Double? {
        if (!prefs.distanceAwareReminder.first()) return null
        val leg = route.currentLeg ?: return null
        val originLat = leg.originLat ?: return null
        val originLon = leg.originLon ?: return null
        val (userLat, userLon) = prefs.lastCoordinate() ?: return null
        return GeoUtils.haversineDistance(userLat, userLon, originLat, originLon)
    }

    // Fires immediately so the user can confirm permission + delivery without
    // waiting for a real departure. Same channel as the real reminder.
    fun sendTest(context: Context) {
        notifyNow(context, "Test reminder", "Route reminders are working. This is a test.")
    }

    // Posts an immediate notification in the reminder channel. Used by the test
    // buttons (plain + distance readout).
    fun notifyNow(context: Context, title: String, body: String) {
        ensureChannel(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(NOTIF_ID, notification)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        context.getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
    }
}
