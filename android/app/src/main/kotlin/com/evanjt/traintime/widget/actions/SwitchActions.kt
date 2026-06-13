package com.evanjt.traintime.widget.actions

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import com.evanjt.traintime.data.api.TrainApi
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.widget.TrainTimeWidget
import com.evanjt.traintime.widget.WidgetDeparture
import com.evanjt.traintime.widget.WidgetFetchResult
import com.evanjt.traintime.widget.WidgetStateDefinition
import com.evanjt.traintime.widget.WidgetStation
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.TransportMode
import kotlinx.coroutines.withTimeoutOrNull

// Ports of SwitchModeIntent / SwitchStationIntent. Switching never
// touches fetchTime: it does not extend the 60 s active window.

internal fun Departure.toWidgetDeparture() = WidgetDeparture(
    destination = destination,
    departureTimestamp = departureTimestamp ?: 0,
    delay = delay,
    platform = platform,
    platformChanged = platformChanged,
    lineNumber = lineNumber,
)

// Favourites first, then the full list — same order as the iOS widget.
internal suspend fun fetchStationDepartures(context: Context, station: WidgetStation): WidgetStation? {
    val favourites = FavouritesStore(context)
    val favParam = favourites.favouritesParam(station.id)
    val result = runCatching { TrainApi.shared.fetchDepartures(station.id, favParam) }.getOrNull() ?: return null
    val favDeps = result.favourites.ifEmpty {
        favourites.extractFavourites(result.departures, station.id)
    }
    val deps = (favDeps + result.departures).map { it.toWidgetDeparture() }
    return WidgetStation(id = station.id, name = station.name, departures = deps)
}

private suspend fun applySwitch(
    context: Context,
    transform: suspend (WidgetFetchResult) -> WidgetFetchResult,
) {
    val result = WidgetStateDefinition.read(context).result ?: return
    val updated = transform(result)
    WidgetStateDefinition.update(context) { it.copy(result = updated, dormant = false) }
    TrainTimeWidget().updateAll(context)
}

class SwitchModeAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        applySwitch(context) { result ->
            val modes = result.availableModes
            if (modes.size <= 1) return@applySwitch result

            val currentIdx = modes.indexOf(result.selectedMode).coerceAtLeast(0)
            val nextMode = modes[(currentIdx + 1) % modes.size]
            var updated = result.withSelection(nextMode.raw, 0)

            val stations = updated.stations(nextMode)
            if (stations.isNotEmpty() && stations[0].departures.isEmpty()) {
                withTimeoutOrNull(5000) { fetchStationDepartures(context, stations[0]) }?.let {
                    updated = updated.withStation(nextMode, 0, it)
                }
            }
            updated
        }
    }
}

class SwitchStationAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        applySwitch(context) { result ->
            val mode = result.selectedMode
            val stations = result.stations(mode)
            if (stations.size <= 1) return@applySwitch result

            val nextIdx = (result.selectedStationIndex + 1) % stations.size
            var updated = result.withSelection(result.selectedModeRaw, nextIdx)

            if (stations[nextIdx].departures.isEmpty()) {
                withTimeoutOrNull(5000) { fetchStationDepartures(context, stations[nextIdx]) }?.let {
                    updated = updated.withStation(mode, nextIdx, it)
                }
            }
            updated
        }
    }
}
