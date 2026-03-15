package ch.traintime.phone.widget

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import ch.traintime.shared.api.TrainAPIService
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.tasks.await

class WidgetWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    @SuppressLint("MissingPermission")
    override suspend fun doWork(): Result {
        return try {
            // Get location
            val fusedClient = LocationServices.getFusedLocationProviderClient(context)
            val location: Location = fusedClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                CancellationTokenSource().token
            ).await() ?: return Result.failure()

            // Fetch stations
            val result = TrainAPIService.fetchStations(location.latitude, location.longitude)
            val allStations = result.train + result.bus + result.tram + result.special
            val station = allStations.firstOrNull { !it.embeddedDepartures.isNullOrEmpty() }
                ?: allStations.firstOrNull()
                ?: return Result.failure()

            // Get departures
            val deps = if (!station.embeddedDepartures.isNullOrEmpty()) {
                station.embeddedDepartures!!.map { dep ->
                    WidgetDeparture(
                        destination = dep.destination,
                        departureTimestamp = dep.departureTimestamp ?: 0,
                        delay = dep.delay,
                        platform = dep.platform,
                        platformChanged = dep.platformChanged,
                        lineNumber = dep.lineNumber
                    )
                }
            } else {
                val fetched = TrainAPIService.fetchDepartures(station.id ?: "")
                fetched.map { dep ->
                    WidgetDeparture(
                        destination = dep.destination,
                        departureTimestamp = dep.departureTimestamp ?: 0,
                        delay = dep.delay,
                        platform = dep.platform,
                        platformChanged = dep.platformChanged,
                        lineNumber = dep.lineNumber
                    )
                }
            }

            // Save and update widget
            WidgetStorage.save(context, FetchResult(
                stationName = station.name ?: "Station",
                departures = deps,
                fetchTime = System.currentTimeMillis() / 1000.0
            ))
            TrainTimeWidget().updateAll(context)

            Result.success()
        } catch (e: Exception) {
            Result.failure()
        }
    }
}
