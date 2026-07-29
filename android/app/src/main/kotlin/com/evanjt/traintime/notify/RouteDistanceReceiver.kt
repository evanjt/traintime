package com.evanjt.traintime.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.PendingRouteStore
import com.google.android.gms.location.LocationResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// Receives background location updates from RouteDistanceTracker, stores the
// fresh coordinate, and reschedules the reminder off the new distance. Stops
// itself once the route is gone or the feature is turned off, so it never
// lingers.
class RouteDistanceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val location = LocationResult.extractResult(intent)?.lastLocation ?: return
        val appContext = context.applicationContext
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val prefs = AppPrefs(appContext)
                prefs.saveLastCoordinate(location.latitude, location.longitude)
                val route = PendingRouteStore(appContext).current()
                val active = route != null &&
                    prefs.distanceAwareReminder.first() &&
                    prefs.backgroundReminderTracking.first()
                if (active) {
                    PendingRouteNotifier.schedule(
                        appContext,
                        route!!,
                        System.currentTimeMillis() / 1000,
                        fromLocationUpdate = true,
                    )
                } else {
                    RouteDistanceTracker.stop(appContext)
                }
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION_LOCATION = "com.evanjt.traintime.ROUTE_DISTANCE_LOCATION"
    }
}
