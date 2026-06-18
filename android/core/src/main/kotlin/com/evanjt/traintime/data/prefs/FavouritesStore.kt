package com.evanjt.traintime.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Favourite
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

// Port of apple/TrainTimeWatch/Services/FavouritesStore.swift,
// minus the WCSession sync (no companion device on Android).
class FavouritesStore(context: Context) {
    private val dataStore = context.applicationContext.trainTimeDataStore
    private val json = Json { ignoreUnknownKeys = true }

    val favourites: Flow<List<Favourite>> = dataStore.data.map { prefs ->
        prefs[AppPrefs.KEY_FAVOURITES]?.let { decode(it) } ?: emptyList()
    }

    suspend fun all(): List<Favourite> = favourites.first()

    suspend fun remove(favourite: Favourite) {
        update { list -> list.filterNot { it == favourite } }
    }

    suspend fun isFavourite(stationId: String, lineNumber: String, destination: String): Boolean =
        all().any {
            it.stationId == stationId && it.lineNumber == lineNumber && it.destination == destination
        }

    suspend fun toggle(stationId: String, stationName: String, lineNumber: String, destination: String) {
        update { list ->
            val existing = list.filter {
                it.stationId == stationId && it.lineNumber == lineNumber && it.destination == destination
            }
            if (existing.isNotEmpty()) {
                list - existing.toSet()
            } else if (list.size < MAX_FAVOURITES) {
                list + Favourite(stationId, stationName, lineNumber, destination)
            } else {
                list
            }
        }
    }

    // Overwrite the whole list — used by the Wearable Data Layer sync when the
    // companion device pushes its favourites.
    suspend fun replaceAll(favourites: List<Favourite>) {
        dataStore.edit { it[AppPrefs.KEY_FAVOURITES] = json.encodeToString(favourites) }
    }

    suspend fun favouritesForStation(stationId: String): List<Favourite> =
        all().filter { it.stationId == stationId }

    suspend fun extractFavourites(departures: List<Departure>, stationId: String): List<Departure> =
        extract(favouritesForStation(stationId), departures)

    suspend fun favouritesParam(stationId: String): String? =
        param(favouritesForStation(stationId))

    private suspend fun update(transform: (List<Favourite>) -> List<Favourite>) {
        dataStore.edit { prefs ->
            val current = prefs[AppPrefs.KEY_FAVOURITES]?.let { decode(it) } ?: emptyList()
            prefs[AppPrefs.KEY_FAVOURITES] = json.encodeToString(transform(current))
        }
    }

    private fun decode(raw: String): List<Favourite> =
        runCatching { json.decodeFromString<List<Favourite>>(raw) }.getOrDefault(emptyList())

    companion object {
        const val MAX_FAVOURITES = 20

        // First match per favourite, sorted by departure time.
        fun extract(stationFavs: List<Favourite>, departures: List<Departure>): List<Departure> {
            if (stationFavs.isEmpty()) return emptyList()
            return stationFavs
                .mapNotNull { fav ->
                    departures.firstOrNull {
                        it.lineNumber == fav.lineNumber && it.destination == fav.destination
                    }
                }
                .sortedBy { it.departureTimestamp ?: 0 }
        }

        // "IC8:Brig,IR90:Visp" — server-side filtering param.
        fun param(stationFavs: List<Favourite>): String? {
            if (stationFavs.isEmpty()) return null
            return stationFavs.joinToString(",") { "${it.lineNumber}:${it.destination}" }
        }

        // Keep favourite departures present in the regular list so they repeat
        // in time order. No-op until the server returns a favourites array
        // without also keeping them in `departures`.
        fun merge(favourites: List<Departure>, departures: List<Departure>): List<Departure> {
            if (favourites.isEmpty()) return departures
            val result = departures.toMutableList()
            for (fav in favourites) {
                val present = departures.any {
                    it.lineNumber == fav.lineNumber &&
                        it.destination == fav.destination &&
                        it.departureTimestamp == fav.departureTimestamp
                }
                if (!present) result.add(fav)
            }
            return result.sortedBy { it.departureTimestamp ?: 0 }
        }
    }
}
