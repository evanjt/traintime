package com.evanjt.traintime.data.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.evanjt.traintime.data.model.TransportMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

// Single app-wide DataStore; the widget runs in the same process and
// shares it safely.
val Context.trainTimeDataStore: DataStore<Preferences> by preferencesDataStore(name = "traintime_prefs")

// UserDefaults equivalent: defaultMode, useRoutedDistance, lastLat/lastLon.
class AppPrefs(context: Context) {
    private val dataStore = context.applicationContext.trainTimeDataStore

    val defaultMode: Flow<TransportMode> =
        dataStore.data.map { TransportMode.fromRaw(it[KEY_DEFAULT_MODE] ?: 0) }

    suspend fun defaultModeNow(): TransportMode = defaultMode.first()

    suspend fun setDefaultMode(mode: TransportMode) {
        dataStore.edit { it[KEY_DEFAULT_MODE] = mode.raw }
    }

    val useRoutedDistance: Flow<Boolean> =
        dataStore.data.map { it[KEY_USE_ROUTED_DISTANCE] ?: false }

    suspend fun setUseRoutedDistance(value: Boolean) {
        dataStore.edit { it[KEY_USE_ROUTED_DISTANCE] = value }
    }

    suspend fun lastCoordinate(): Pair<Double, Double>? {
        val prefs = dataStore.data.first()
        val lat = prefs[KEY_LAST_LAT] ?: 0.0
        val lon = prefs[KEY_LAST_LON] ?: 0.0
        return if (lat != 0.0 && lon != 0.0) lat to lon else null
    }

    suspend fun saveLastCoordinate(lat: Double, lon: Double) {
        dataStore.edit {
            it[KEY_LAST_LAT] = lat
            it[KEY_LAST_LON] = lon
        }
    }

    companion object {
        val KEY_DEFAULT_MODE = intPreferencesKey("defaultMode")
        val KEY_USE_ROUTED_DISTANCE = booleanPreferencesKey("useRoutedDistance")
        val KEY_LAST_LAT = doublePreferencesKey("lastLat")
        val KEY_LAST_LON = doublePreferencesKey("lastLon")
        val KEY_FAVOURITES = stringPreferencesKey("favourites_v1")
        val KEY_MY_STATIONS = stringPreferencesKey("myStations_v1")
    }
}
