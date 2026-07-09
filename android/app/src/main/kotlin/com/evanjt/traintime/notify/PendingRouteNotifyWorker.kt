package com.evanjt.traintime.notify

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.net.toUri
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.evanjt.traintime.MainActivity
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.PendingRouteStore
import com.evanjt.traintime.domain.PendingRouteLogic
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// Fires at the scheduled reminder time. Re-reads the store first: the route
// may have been dismissed, replaced, or advanced since scheduling, then
// this run exits quietly.
class PendingRouteNotifyWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val now = System.currentTimeMillis() / 1000
        val route = PendingRouteStore(applicationContext).current() ?: return Result.success()
        val normalized = PendingRouteLogic.normalize(route, now) ?: return Result.success()
        val leg = normalized.currentLeg ?: return Result.success()
        if (normalized.cursor != route.cursor) return Result.success() // stale schedule

        val time = DateTimeFormatter.ofPattern("HH:mm").format(
            Instant.ofEpochSecond(leg.depTs).atZone(ZoneId.of("Europe/Zurich")),
        )
        val line = "${leg.category ?: ""}${leg.lineNumber ?: ""}".ifEmpty { "Train" }
        val tapIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            Intent(
                Intent.ACTION_VIEW,
                "traintime://resumeroute".toUri(),
                applicationContext,
                MainActivity::class.java,
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        PendingRouteNotifier.ensureChannel(applicationContext)
        val builder = NotificationCompat.Builder(applicationContext, PendingRouteNotifier.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("$line to ${normalized.finalDestination}")
            .setContentText("Departs $time from ${leg.originName}")
            .setContentIntent(tapIntent)
            .setAutoCancel(true)

        // Offer "Send to Watch" only when a Garmin is paired (cached by the VM;
        // this worker has no SDK binding). Picking it on the watch runs the
        // PendingIntent on the phone, which wakes the watch app into tracking.
        if (AppPrefs(applicationContext).garminEverConnectedNow()) {
            // Opens the app (not a background service): the Connect IQ SDK only
            // binds to Garmin Connect with the app in the foreground, so the send
            // has to run there. The app then wakes the watch and pushes the route.
            val sendPending = PendingIntent.getActivity(
                applicationContext,
                1,
                Intent(
                    Intent.ACTION_VIEW,
                    "traintime://sendtowatch".toUri(),
                    applicationContext,
                    MainActivity::class.java,
                ),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(android.R.drawable.ic_menu_send, "Send to Watch", sendPending)
        }

        val notification = builder.build()
        applicationContext.getSystemService(NotificationManager::class.java)
            .notify(PendingRouteNotifier.NOTIF_ID, notification)
        return Result.success()
    }
}
