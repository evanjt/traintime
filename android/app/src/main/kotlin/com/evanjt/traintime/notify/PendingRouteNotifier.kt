package com.evanjt.traintime.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.domain.PendingRouteLogic
import java.util.concurrent.TimeUnit

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

    fun schedule(context: Context, route: PendingRoute, nowEpochSeconds: Long) {
        val notifyTs = PendingRouteLogic.notifyTs(route) ?: return cancel(context)
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

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        context.getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
    }
}
