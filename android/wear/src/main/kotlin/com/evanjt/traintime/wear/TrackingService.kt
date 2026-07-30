package com.evanjt.traintime.wear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.domain.LocaleUtil
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

// Keeps the tracking countdown alive when the wrist drops, the Wear analog of
// the Apple watch's WKExtendedRuntimeSession. A location-typed foreground
// service (tracking actively uses high-accuracy GPS) carrying an OngoingActivity
// so the countdown surfaces on the watch face.
class TrackingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    // The notification renders outside any activity, so the in-app language
    // override reaches it only through LocaleUtil with the AppPrefs tag.
    private fun trackingLabel(): String {
        val tag = runBlocking { AppPrefs(this@TrackingService).appLanguage.first() }
        return LocaleUtil.localised(this, tag).getString(R.string.tracking_channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: trackingLabel()
        val leaveByMs = intent?.getLongExtra(EXTRA_LEAVE_BY, 0L) ?: 0L
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIF_ID, buildNotification(title, leaveByMs), type)
        return START_STICKY
    }

    // `leaveByMs` is the wall-clock moment to leave (effective departure − walk); 0
    // while the walk is unknown. When known, both the notification chronometer and
    // the watch-face OngoingActivity count down to it, mirroring the Android phone
    // notification's leave-by countdown. The OngoingActivity timer is elapsedRealtime-
    // based, so the wall-clock target is converted at build time.
    private fun buildNotification(title: String, leaveByMs: Long): Notification {
        val label = trackingLabel()
        ensureChannel(label)
        val touchIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(label)
            .setContentText(title)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(touchIntent)

        val useTimer = leaveByMs > 0
        if (useTimer) {
            builder.setWhen(leaveByMs).setShowWhen(true)
                .setUsesChronometer(true).setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }

        val status = if (useTimer) {
            val timeZeroElapsed = SystemClock.elapsedRealtime() + (leaveByMs - System.currentTimeMillis())
            Status.Builder()
                .addTemplate("#dest# · #timer#")
                .addPart("dest", Status.TextPart(title))
                .addPart("timer", Status.TimerPart(timeZeroElapsed))
                .build()
        } else {
            Status.Builder().addTemplate(title).build()
        }

        val ongoing = OngoingActivity.Builder(applicationContext, NOTIF_ID, builder)
            .setStaticIcon(android.R.drawable.ic_menu_mylocation)
            .setTouchIntent(touchIntent)
            .setStatus(status)
            .build()
        ongoing.apply(applicationContext)

        return builder.build()
    }

    private fun ensureChannel(name: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    companion object {
        private const val CHANNEL_ID = "tracking"
        private const val NOTIF_ID = 1

        fun start(context: Context, title: String, leaveByMs: Long = 0L) {
            val intent = Intent(context, TrackingService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_LEAVE_BY, leaveByMs)
            runCatching { ContextCompat.startForegroundService(context, intent) }
        }

        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, TrackingService::class.java)) }
        }

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_LEAVE_BY = "leaveBy"
    }
}
