package com.evanjt.traintime.data.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
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

    // When on, the phone mirrors its state (tracked train, mode, station) and its
    // location to a connected watch. Optional overlay, off means the watch runs
    // entirely on its own. Default on.
    val mirrorToWatch: Flow<Boolean> =
        dataStore.data.map { it[KEY_MIRROR_TO_WATCH] ?: true }

    suspend fun setMirrorToWatch(value: Boolean) {
        dataStore.edit { it[KEY_MIRROR_TO_WATCH] = value }
    }

    // First-launch walkthrough flag (phone only). False until the user finishes
    // or skips onboarding.
    val hasSeenOnboarding: Flow<Boolean> =
        dataStore.data.map { it[KEY_HAS_SEEN_ONBOARDING] ?: false }

    suspend fun markOnboardingSeen() {
        dataStore.edit { it[KEY_HAS_SEEN_ONBOARDING] = true }
    }

    // Re-arms the walkthrough so the "Replay walkthrough" Settings row can show it again.
    suspend fun markOnboardingUnseen() {
        dataStore.edit { it[KEY_HAS_SEEN_ONBOARDING] = false }
    }

    // Manual appearance override (phone only): "system" follows the OS, "light"
    // and "dark" force the theme.
    val appearanceMode: Flow<String> =
        dataStore.data.map { it[KEY_APPEARANCE_MODE] ?: "system" }

    suspend fun setAppearanceMode(value: String) {
        dataStore.edit { it[KEY_APPEARANCE_MODE] = value }
    }

    // Review gating: count tracking sessions so a brand-new user isn't prompted,
    // and remember the version we last prompted on so we only ask once per release.
    val reviewTrackCount: Flow<Int> =
        dataStore.data.map { it[KEY_REVIEW_TRACK_COUNT] ?: 0 }

    suspend fun incrementReviewTrackCount() {
        dataStore.edit { it[KEY_REVIEW_TRACK_COUNT] = (it[KEY_REVIEW_TRACK_COUNT] ?: 0) + 1 }
    }

    val reviewPromptedVersion: Flow<String> =
        dataStore.data.map { it[KEY_REVIEW_PROMPTED_VERSION] ?: "" }

    suspend fun setReviewPromptedVersion(value: String) {
        dataStore.edit { it[KEY_REVIEW_PROMPTED_VERSION] = value }
    }

    // Stamped once at first start so the review prompt can wait out a minimum
    // install age. For existing installs the clock starts at the first
    // post-update launch, which is acceptable and self-correcting.
    val firstLaunchTs: Flow<Long> =
        dataStore.data.map { it[KEY_FIRST_LAUNCH_TS] ?: 0L }

    suspend fun ensureFirstLaunchTimestamp(now: Long = System.currentTimeMillis()) {
        dataStore.edit {
            if ((it[KEY_FIRST_LAUNCH_TS] ?: 0L) == 0L) it[KEY_FIRST_LAUNCH_TS] = now
        }
    }

    val reviewSnoozeUntil: Flow<Long> =
        dataStore.data.map { it[KEY_REVIEW_SNOOZE_UNTIL] ?: 0L }

    suspend fun setReviewSnoozeUntil(value: Long) {
        dataStore.edit { it[KEY_REVIEW_SNOOZE_UNTIL] = value }
    }

    val reviewOptOut: Flow<Boolean> =
        dataStore.data.map { it[KEY_REVIEW_OPT_OUT] ?: false }

    suspend fun setReviewOptOut(value: Boolean) {
        dataStore.edit { it[KEY_REVIEW_OPT_OUT] = value }
    }

    // A Wear watch has paired with this phone at least once, drives the grey
    // "known but disconnected" indicator (no SDK lookup exists, unlike Garmin).
    val hasKnownWearNode: Flow<Boolean> =
        dataStore.data.map { it[KEY_HAS_KNOWN_WEAR_NODE] ?: false }

    suspend fun markKnownWearNode() {
        dataStore.edit { it[KEY_HAS_KNOWN_WEAR_NODE] = true }
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
        val KEY_MIRROR_TO_WATCH = booleanPreferencesKey("mirrorToWatch")
        val KEY_HAS_SEEN_ONBOARDING = booleanPreferencesKey("hasSeenOnboarding")
        val KEY_APPEARANCE_MODE = stringPreferencesKey("appearanceMode")
        val KEY_REVIEW_TRACK_COUNT = intPreferencesKey("reviewTrackCount")
        val KEY_REVIEW_PROMPTED_VERSION = stringPreferencesKey("reviewPromptedVersion")
        val KEY_FIRST_LAUNCH_TS = longPreferencesKey("firstLaunchTs")
        val KEY_REVIEW_SNOOZE_UNTIL = longPreferencesKey("reviewSnoozeUntil")
        val KEY_REVIEW_OPT_OUT = booleanPreferencesKey("reviewOptOut")
        val KEY_HAS_KNOWN_WEAR_NODE = booleanPreferencesKey("hasKnownWearNode")
        val KEY_LAST_LAT = doublePreferencesKey("lastLat")
        val KEY_LAST_LON = doublePreferencesKey("lastLon")
        val KEY_FAVOURITES = stringPreferencesKey("favourites_v1")
        val KEY_MY_STATIONS = stringPreferencesKey("myStations_v1")
        val KEY_PENDING_ROUTES = stringPreferencesKey("pendingRoutes_v1")
    }
}
