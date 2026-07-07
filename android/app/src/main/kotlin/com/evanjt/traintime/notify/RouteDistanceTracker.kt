package com.evanjt.traintime.notify

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

// Cheap background distance tracking for the distance-aware route reminder.
// Requests balanced-power fused updates that only fire on real movement
// (250 m filter), delivered to RouteDistanceReceiver which recomputes the lead
// and reschedules. The SLC analog of the iOS path. Active only while a
// distance-aware route with background tracking exists.
object RouteDistanceTracker {
    private const val REQUEST_CODE = 4711

    fun start(context: Context) {
        if (!hasBackgroundLocation(context)) return
        val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 3 * 60 * 1000L)
            .setMinUpdateIntervalMillis(60 * 1000L)
            .setMinUpdateDistanceMeters(250f)
            .build()
        try {
            LocationServices.getFusedLocationProviderClient(context)
                .requestLocationUpdates(request, pendingIntent(context))
        } catch (_: SecurityException) {
            // Permission revoked between the check and the call; nothing to do.
        }
    }

    fun stop(context: Context) {
        LocationServices.getFusedLocationProviderClient(context)
            .removeLocationUpdates(pendingIntent(context))
    }

    // Below API 29 there is no separate background-location permission; fine
    // location covers it. On 29+ it must be granted explicitly.
    fun hasBackgroundLocation(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, RouteDistanceReceiver::class.java)
            .setAction(RouteDistanceReceiver.ACTION_LOCATION)
        // Mutable so the location provider can fill in the result extra.
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }
}
