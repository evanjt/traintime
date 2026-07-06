package com.evanjt.traintime.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import com.evanjt.traintime.data.model.PendingRoute
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

// Persists the queued shared route (FavouritesStore pattern). Stored as a
// JSON array so a later multi-route version is a cap change, not a
// migration; 0.6.0 keeps exactly one.
class PendingRouteStore(context: Context) {
    private val dataStore = context.applicationContext.trainTimeDataStore
    private val json = Json { ignoreUnknownKeys = true }

    val pending: Flow<PendingRoute?> = dataStore.data.map { prefs ->
        prefs[AppPrefs.KEY_PENDING_ROUTES]?.let { decode(it) }?.firstOrNull()
    }

    suspend fun current(): PendingRoute? = pending.first()

    suspend fun save(route: PendingRoute) {
        dataStore.edit { it[AppPrefs.KEY_PENDING_ROUTES] = json.encodeToString(listOf(route)) }
    }

    // Transform the stored route; returning null clears it. Used by
    // normalize/advance so read-modify-write stays atomic within the edit.
    suspend fun update(transform: (PendingRoute) -> PendingRoute?) {
        dataStore.edit { prefs ->
            val current = prefs[AppPrefs.KEY_PENDING_ROUTES]?.let { decode(it) }?.firstOrNull()
                ?: return@edit
            val next = transform(current)
            if (next == null) {
                prefs.remove(AppPrefs.KEY_PENDING_ROUTES)
            } else if (next != current) {
                prefs[AppPrefs.KEY_PENDING_ROUTES] = json.encodeToString(listOf(next))
            }
        }
    }

    // Toggle a leg's track/notify state from the route view. The caller
    // reschedules the reminder afterwards (notifyTs now skips muted legs).
    suspend fun setLegMuted(index: Int, muted: Boolean) {
        update { route ->
            val set = route.mutedLegIndices.toMutableSet()
            if (muted) set.add(index) else set.remove(index)
            route.copy(mutedLegIndices = set.sorted())
        }
    }

    suspend fun clear() {
        dataStore.edit { it.remove(AppPrefs.KEY_PENDING_ROUTES) }
    }

    // Wearable Data Layer apply path: overwrite without re-sync.
    suspend fun replaceFromSync(route: PendingRoute?) {
        if (route == null) clear() else save(route)
    }

    private fun decode(raw: String): List<PendingRoute> =
        runCatching { json.decodeFromString<List<PendingRoute>>(raw) }.getOrDefault(emptyList())
}
