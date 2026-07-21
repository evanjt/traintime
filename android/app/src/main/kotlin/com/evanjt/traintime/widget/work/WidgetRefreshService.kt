package com.evanjt.traintime.widget.work

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.LatLon
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.domain.LocaleUtil
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

// Short-lived location foreground service for widget refreshes.
// A widget tap is an exempted background FGS start, and while-in-use
// location permission is honoured inside a location-type FGS, so the
// widget gets a live fix without ACCESS_BACKGROUND_LOCATION. One fix
// (10 s budget, mirroring the iOS RefreshIntent), refresh, stop.
class WidgetRefreshService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        scope.launch {
            try {
                val location = getCurrentLocation() ?: WidgetRefresher.resolveCachedLocation(this@WidgetRefreshService)
                WidgetRefresher.refresh(this@WidgetRefreshService, location)
            } finally {
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun startInForeground() {
        // Foreground-service notification renders outside an activity, so resolve
        // its strings through a context wrapped in the stored language tag.
        val ctx = LocaleUtil.localised(this, runBlocking { AppPrefs(this@WidgetRefreshService).appLanguage.first() })
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, ctx.getString(R.string.widget_refresh_channel), NotificationManager.IMPORTANCE_LOW),
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(ctx.getString(R.string.updating_departures))
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun getCurrentLocation(): LatLon? {
        val hasPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) return null

        val fused = LocationServices.getFusedLocationProviderClient(this)
        val cancellation = CancellationTokenSource()
        val location = withTimeoutOrNull(10_000) {
            runCatching {
                fused.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cancellation.token).await()
            }.getOrNull()
        }
        cancellation.cancel()
        return location?.let { LatLon(it.latitude, it.longitude) }
    }

    companion object {
        private const val CHANNEL_ID = "widget_refresh"
        private const val NOTIFICATION_ID = 1001

        // Widget-tap FGS start can still be refused (rare); callers fall
        // back to the cached-location worker.
        fun start(context: Context): Boolean = runCatching {
            ContextCompat.startForegroundService(
                context,
                Intent(context, WidgetRefreshService::class.java),
            )
            true
        }.getOrDefault(false)
    }
}
