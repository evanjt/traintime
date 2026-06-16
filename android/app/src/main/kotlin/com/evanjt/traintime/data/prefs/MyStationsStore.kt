package com.evanjt.traintime.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import com.evanjt.traintime.data.model.PinnedStation
import com.evanjt.traintime.data.model.Station
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

// Unified "My stations": stations the user pins. A pinned station bubbles to the
// front of the nearby list (and becomes the default shown station) when it turns
// up among the downloaded results. Mirrors FavouritesStore's plumbing; the widget
// shares the same DataStore.
class MyStationsStore(context: Context) {
    private val dataStore = context.applicationContext.trainTimeDataStore
    private val json = Json { ignoreUnknownKeys = true }

    val stations: Flow<List<PinnedStation>> = dataStore.data.map { prefs ->
        prefs[AppPrefs.KEY_MY_STATIONS]?.let { decode(it) } ?: emptyList()
    }

    suspend fun all(): List<PinnedStation> = stations.first()

    suspend fun ids(): Set<String> = all().map { it.id }.toSet()

    suspend fun toggle(station: Station) {
        val name = station.name ?: return
        update { list ->
            if (list.any { it.id == station.id }) {
                list.filterNot { it.id == station.id }
            } else if (list.size < MAX) {
                list + PinnedStation(station.id, name, station.lat, station.lon)
            } else {
                list
            }
        }
    }

    suspend fun remove(id: String) {
        update { list -> list.filterNot { it.id == id } }
    }

    private suspend fun update(transform: (List<PinnedStation>) -> List<PinnedStation>) {
        dataStore.edit { prefs ->
            val current = prefs[AppPrefs.KEY_MY_STATIONS]?.let { decode(it) } ?: emptyList()
            prefs[AppPrefs.KEY_MY_STATIONS] = json.encodeToString(transform(current))
        }
    }

    private fun decode(raw: String): List<PinnedStation> =
        runCatching { json.decodeFromString<List<PinnedStation>>(raw) }.getOrDefault(emptyList())

    companion object {
        const val MAX = 10

        // Bubble pinned ids to the front, preserving the API's distance order
        // within each group. Shared by the app and the widget fetch paths.
        fun reorder(stations: List<Station>, pinnedIds: Set<String>): List<Station> {
            if (pinnedIds.isEmpty()) return stations
            val (pinned, rest) = stations.partition { it.id in pinnedIds }
            return pinned + rest
        }
    }
}
