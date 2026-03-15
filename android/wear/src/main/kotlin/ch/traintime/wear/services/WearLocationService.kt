package ch.traintime.wear.services

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import com.google.android.gms.location.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

class WearLocationService(private val context: Context) {
    private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
    private val prefs: SharedPreferences = context.getSharedPreferences("traintime_location", Context.MODE_PRIVATE)
    private var locationCallback: LocationCallback? = null

    var location: Location? = null
        private set
    var heading: Double? = null
        private set

    private val _locationFlow = MutableStateFlow<Location?>(null)
    val locationFlow: Flow<Location?> = _locationFlow

    init {
        val cachedLat = prefs.getFloat("lastLat", Float.NaN)
        val cachedLon = prefs.getFloat("lastLon", Float.NaN)
        if (!cachedLat.isNaN() && !cachedLon.isNaN()) {
            val cached = Location("cache").apply {
                latitude = cachedLat.toDouble()
                longitude = cachedLon.toDouble()
                accuracy = -1f
            }
            location = cached
            _locationFlow.value = cached
        }
    }

    @SuppressLint("MissingPermission")
    fun start() {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000L)
            .setMinUpdateDistanceMeters(5f)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let { loc ->
                    location = loc
                    _locationFlow.value = loc
                    if (loc.hasSpeed() && loc.speed > 0.5f && loc.hasBearing()) {
                        heading = loc.bearing.toDouble() * Math.PI / 180.0
                    }
                }
            }
        }

        fusedClient.requestLocationUpdates(request, locationCallback!!, context.mainLooper)
    }

    fun stop() {
        locationCallback?.let { fusedClient.removeLocationUpdates(it) }
        locationCallback = null
    }

    fun saveLastKnown() {
        location?.let { loc ->
            prefs.edit()
                .putFloat("lastLat", loc.latitude.toFloat())
                .putFloat("lastLon", loc.longitude.toFloat())
                .apply()
        }
    }
}
