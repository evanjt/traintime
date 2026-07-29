package com.evanjt.traintime.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.PendingRouteStore
import com.evanjt.traintime.data.sbb.SharedRoute
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.LocaleUtil
import com.evanjt.traintime.domain.PendingRouteLogic
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

// The scheduled reminder split into its parts, for the in-app readout. walkMin
// is null outside distance-aware mode (nothing to break out); bufferMin is the
// user's chosen lead. Distinct from the raw notifyTs so the chip can colour the
// calculated walk time apart from the fixed buffer.
data class NotifyPlan(
    val notifyTs: Long,
    val walkMin: Int?,
    val bufferMin: Int,
)

// Schedules the "your train leaves soon" heads-up for a queued shared route.
// WorkManager rather than an exact alarm: it persists across process death
// and reboot, and inexact timing is fine for a 15-minute lead.
object PendingRouteNotifier {
    const val CHANNEL_ID = "pending_route"
    const val NOTIF_ID = 2
    private const val WORK_NAME = "pending-route-notify"

    // Notifications render outside any activity, so the per-app language override
    // (AppCompatDelegate) may not reach here on pre-33 devices. Resolve strings
    // through a context wrapped in the stored language tag.
    private fun localised(context: Context): Context {
        val tag = runBlocking { AppPrefs(context).appLanguage.first() }
        return LocaleUtil.localised(context, tag)
    }

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                localised(context).getString(R.string.channel_saved_routes),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    // Persist a synthesised route as a saved reminder and schedule it, without a
    // running ViewModel. Used by the watch's remind-on-phone path, which can
    // arrive with the app closed. Replaces any existing saved route (0.6.0 keeps
    // one); the VM's pending-route collector refreshes the chip if the app is up.
    suspend fun saveAndSchedule(context: Context, route: SharedRoute, nowEpochSeconds: Long): Boolean {
        val index = route.targetRideLegIndex(nowEpochSeconds) ?: return false
        val pending = PendingRoute.from(
            route = route,
            targetLegIndex = index,
            id = UUID.randomUUID().toString(),
            createdTs = nowEpochSeconds,
            sourceUrl = null,
        ).copy(status = PendingRoute.STATUS_SAVED)
        PendingRouteStore(context).save(pending)
        schedule(context, pending, nowEpochSeconds)
        return true
    }

    suspend fun schedule(
        context: Context,
        route: PendingRoute,
        nowEpochSeconds: Long,
        fromLocationUpdate: Boolean = false,
    ) {
        val prefs = AppPrefs(context)
        val savedLead = prefs.routeReminderLeadMinutes.first() * 60L
        val connectionLead = prefs.connectionReminderLeadMinutes.first() * 60L
        val distance = userDistanceMeters(prefs, route)
        val notifyTs = PendingRouteLogic.notifyTs(route, savedLead, connectionLead, distance)
            ?: return cancel(context)
        val delay = notifyTs - nowEpochSeconds
        if (delay <= 0) {
            // Inside the window. On a (re)save that means the user just saw the
            // route, so clear any stale reminder. A background fix landing here
            // must not clobber anything: the previously scheduled work still
            // fires, and a reminder already in the shade stays there.
            if (!fromLocationUpdate) cancel(context)
            return
        }
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

    // The reminder split into walk + buffer for the chip and resume prompt. Uses
    // the same distance and leads as schedule, so the readout matches what fires.
    // walkMin is null in static mode or for a connection leg (no walk component).
    suspend fun nextNotifyPlan(context: Context, route: PendingRoute): NotifyPlan? {
        val prefs = AppPrefs(context)
        val savedLead = prefs.routeReminderLeadMinutes.first() * 60L
        val connectionLead = prefs.connectionReminderLeadMinutes.first() * 60L
        val distance = userDistanceMeters(prefs, route)
        val notifyTs = PendingRouteLogic.notifyTs(route, savedLead, connectionLead, distance) ?: return null
        val connection = PendingRouteLogic.isConnectionLeg(route)
        val walkMin = if (distance != null && !connection) GeoUtils.walkMinutes(distance).roundToInt() else null
        val bufferSec = if (connection) connectionLead else savedLead
        return NotifyPlan(notifyTs, walkMin, (bufferSec / 60).toInt())
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
        val ctx = localised(context)
        notifyNow(context, ctx.getString(R.string.test_reminder_title), ctx.getString(R.string.test_reminder_body))
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
