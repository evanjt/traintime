package com.evanjt.traintime.widget.work

import android.annotation.SuppressLint
import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.evanjt.traintime.data.api.TrainApi
import com.evanjt.traintime.data.model.LatLon
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.widget.TrainTimeWidget
import com.evanjt.traintime.widget.WidgetFetchResult
import com.evanjt.traintime.widget.WidgetStateDefinition
import com.evanjt.traintime.widget.WidgetStation
import com.evanjt.traintime.widget.actions.fetchStationDepartures
import com.evanjt.traintime.widget.actions.toWidgetDeparture
import com.google.android.gms.location.LocationServices
import java.time.Duration
import kotlinx.coroutines.tasks.await

// Port of RefreshIntent.perform(): locate, fetch nearby stations,
// preserve the previous mode/station selection when still valid,
// backfill departures for the selected station, save the snapshot,
// re-render, and schedule the dormancy revert.
object WidgetRefresher {

    suspend fun refresh(context: Context, location: LatLon?) {
        try {
            val coordinate = location ?: resolveCachedLocation(context)
            if (coordinate == null) {
                finish(context)
                return
            }

            val result = runCatching {
                TrainApi.shared.fetchStations(coordinate.lat, coordinate.lon)
            }.getOrNull()
            if (result == null) {
                finish(context)
                return
            }

            val previous = WidgetStateDefinition.read(context).result

            var snapshot = WidgetFetchResult(
                train = result.train.toWidgetStations(),
                bus = result.bus.toWidgetStations(),
                tram = result.tram.toWidgetStations(),
                special = result.special.toWidgetStations(),
                selectedModeRaw = previous?.selectedModeRaw ?: TransportMode.TRAIN.raw,
                selectedStationIndex = previous?.selectedStationIndex ?: 0,
                fetchTime = System.currentTimeMillis() / 1000,
            )

            // Validate selection, preserving previous when still valid
            var mode = snapshot.selectedMode
            if (snapshot.stations(mode).isEmpty()) {
                snapshot.availableModes.firstOrNull()?.let { mode = it }
                snapshot = snapshot.withSelection(mode.raw, 0)
            } else if (snapshot.selectedStationIndex >= snapshot.stations(mode).size) {
                snapshot = snapshot.withSelection(mode.raw, 0)
            }

            // Backfill departures for the selected station if none embedded
            val stations = snapshot.stations(snapshot.selectedMode)
            val idx = snapshot.selectedStationIndex
            if (idx < stations.size && stations[idx].departures.isEmpty()) {
                fetchStationDepartures(context, stations[idx])?.let {
                    snapshot = snapshot.withStation(snapshot.selectedMode, idx, it)
                }
            }

            val final = snapshot
            WidgetStateDefinition.update(context) {
                it.copy(result = final, refreshStartedAt = 0, dormant = false)
            }
            TrainTimeWidget().updateAll(context)
            scheduleTick(context)
        } catch (e: Exception) {
            finish(context)
        }
    }

    // Re-render once a minute so the countdown ticks; the worker chains itself
    // and flips to dormant at the end of the active window.
    fun scheduleTick(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            WidgetTickWorker.UNIQUE_NAME,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<WidgetTickWorker>()
                .setInitialDelay(Duration.ofSeconds(60))
                .build(),
        )
    }

    private suspend fun finish(context: Context) {
        WidgetStateDefinition.update(context) { it.copy(refreshStartedAt = 0) }
        TrainTimeWidget().updateAll(context)
    }

    // Fallback location tiers: opportunistic last-known fix, then the
    // coordinate cached by the app on its last station search.
    @SuppressLint("MissingPermission")
    suspend fun resolveCachedLocation(context: Context): LatLon? {
        val fused = LocationServices.getFusedLocationProviderClient(context)
        val lastKnown = runCatching { fused.lastLocation.await() }.getOrNull()
        if (lastKnown != null) return LatLon(lastKnown.latitude, lastKnown.longitude)
        return AppPrefs(context).lastCoordinate()?.let { (lat, lon) -> LatLon(lat, lon) }
    }

    private fun List<Station>.toWidgetStations(): List<WidgetStation> =
        mapNotNull { station ->
            val name = station.name ?: return@mapNotNull null
            WidgetStation(
                id = station.id,
                name = name,
                departures = station.embeddedDepartures?.map { it.toWidgetDeparture() } ?: emptyList(),
            )
        }
}
