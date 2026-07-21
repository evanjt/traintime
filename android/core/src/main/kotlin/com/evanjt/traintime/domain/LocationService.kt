package com.evanjt.traintime.domain

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import androidx.core.content.ContextCompat
import com.evanjt.traintime.SwissBounds
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.data.model.LatLon
import com.evanjt.traintime.data.prefs.AppPrefs
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlin.math.abs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await

// Port of PhoneLocationService.swift on the fused location provider.
// Coarse-ish (balanced) accuracy finds stations without waiting for GPS
// convergence; raised to high accuracy while tracking a departure.
class LocationService(context: Context, private val prefs: AppPrefs) {
    private val appContext = context.applicationContext
    private val fused = LocationServices.getFusedLocationProviderClient(appContext)

    private companion object {
        // OS last-known fixes older than this are seeded as cached, not live.
        const val SEED_MAX_AGE_MS = 120_000L
    }

    private val _coordinate = MutableStateFlow<LatLon?>(null)
    val coordinate: StateFlow<LatLon?> = _coordinate

    // Negative accuracy marks a cached (not live) coordinate, as on iOS.
    var horizontalAccuracy: Double? = null
        private set
    var speed: Double? = null
        private set
    var heading: Double? = null // radians, only when moving
        private set

    private val _authorizationDenied = MutableStateFlow(false)
    val authorizationDenied: StateFlow<Boolean> = _authorizationDenied

    private var updatesActive = false
    private var tracking = false

    val gpsQuality: GpsQuality
        get() = if (loadedFromCache) GpsQuality.LAST_KNOWN else GpsQuality.from(horizontalAccuracy)

    val loadedFromCache: Boolean
        get() = _coordinate.value != null && horizontalAccuracy == -1.0

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            onFix(location)
        }
    }

    private fun onFix(location: Location) {
        if (abs(location.latitude) > 90 || abs(location.longitude) > 180) return
        horizontalAccuracy =
            if (location.hasAccuracy()) location.accuracy.toDouble() else null
        speed = location.speed.toDouble()
        if (location.speed > 0.5 && location.hasBearing()) {
            heading = Math.toRadians(location.bearing.toDouble())
        }
        _coordinate.value = LatLon(location.latitude, location.longitude)
    }

    val hasPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    fun onPermissionDenied() {
        _authorizationDenied.value = true
    }

    // Seed from the OS last-known fix (or the persisted coordinate) so
    // stations can show immediately, then start live updates.
    @SuppressLint("MissingPermission")
    suspend fun start() {
        if (!hasPermission) {
            _authorizationDenied.value = true
            return
        }
        _authorizationDenied.value = false

        if (_coordinate.value == null) {
            val seeded = runCatching { fused.lastLocation.await() }.getOrNull()
            if (seeded != null && System.currentTimeMillis() - seeded.time <= SEED_MAX_AGE_MS) {
                onFix(seeded)
            } else if (seeded != null && abs(seeded.latitude) <= 90 && abs(seeded.longitude) <= 180) {
                // An old OS fix still finds nearby stations fast, but it keeps
                // its original (often good) accuracy while being from wherever
                // the phone last resolved — possibly another city. Mark it
                // cached so nothing downstream treats it as proof of position.
                horizontalAccuracy = -1.0
                _coordinate.value = LatLon(seeded.latitude, seeded.longitude)
            } else {
                prefs.lastCoordinate()?.let { (lat, lon) ->
                    horizontalAccuracy = -1.0
                    _coordinate.value = LatLon(lat, lon)
                }
            }
        }

        startUpdates()
    }

    fun stop() {
        fused.removeLocationUpdates(callback)
        updatesActive = false
    }

    fun setTrackingAccuracy(tracking: Boolean) {
        if (this.tracking == tracking) return
        this.tracking = tracking
        if (updatesActive) startUpdates()
    }

    @SuppressLint("MissingPermission")
    private fun startUpdates() {
        if (!hasPermission) return
        fused.removeLocationUpdates(callback)
        val request = if (tracking) {
            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2000L).build()
        } else {
            LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 5000L).build()
        }
        fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
        updatesActive = true
    }

    fun hasMovedSignificantly(from: LatLon): Boolean {
        val current = _coordinate.value ?: return false
        val dLat = abs(current.lat - from.lat)
        val dLon = abs(current.lon - from.lon)
        return dLat > 0.0045 || dLon > 0.006
    }

    val isInSwitzerland: Boolean
        get() = _coordinate.value?.let { SwissBounds.contains(it.lat, it.lon) } ?: false

    suspend fun saveLastKnownCoordinate() {
        _coordinate.value?.let { prefs.saveLastCoordinate(it.lat, it.lon) }
    }
}
