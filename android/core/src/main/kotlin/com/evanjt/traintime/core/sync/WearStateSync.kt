package com.evanjt.traintime.core.sync

import android.content.Context
import com.evanjt.traintime.data.model.Favourite
import com.evanjt.traintime.data.model.PinnedStation
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.data.prefs.MyStationsStore
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString

data class SyncPayload(
    val favourites: List<Favourite>,
    val myStations: List<PinnedStation>,
    val defaultMode: Int,
)

// Bidirectional favourites / pinned-stations / default-mode sync over the
// Wearable Data Layer — the Android analog of WCSession updateApplicationContext.
// Track commands go over MessageClient (sendTrack), like PhoneWatchService.
//
// A process-wide singleton so the running ViewModel (which pushes on local
// edits) and the WearableListenerService (which applies remote edits) share one
// echo-guard: a push is skipped when its content matches what we last sent or
// last received, so an applied remote change doesn't bounce straight back.
class WearStateSync private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val favStore = FavouritesStore(appContext)
    private val myStore = MyStationsStore(appContext)
    private val prefs = AppPrefs(appContext)

    private val dataClient = Wearable.getDataClient(appContext)
    private val messageClient = Wearable.getMessageClient(appContext)
    private val nodeClient = Wearable.getNodeClient(appContext)

    @Volatile private var lastSent: SyncPayload? = null
    @Volatile private var lastReceived: SyncPayload? = null

    private suspend fun currentPayload(): SyncPayload = SyncPayload(
        favourites = favStore.all(),
        myStations = myStore.all(),
        defaultMode = prefs.defaultModeNow().raw,
    )

    suspend fun pushState() {
        val payload = currentPayload()
        if (payload == lastSent || payload == lastReceived) return
        val request = PutDataMapRequest.create(WearSync.STATE_PATH).apply {
            dataMap.putString(WearSync.KEY_FAVOURITES, WearSync.json.encodeToString(payload.favourites))
            dataMap.putString(WearSync.KEY_MY_STATIONS, WearSync.json.encodeToString(payload.myStations))
            dataMap.putInt(WearSync.KEY_DEFAULT_MODE, payload.defaultMode)
        }.asPutDataRequest().setUrgent()
        runCatching { dataClient.putDataItem(request).await() }
        lastSent = payload
    }

    suspend fun applyReceived(map: DataMap) {
        val favourites = map.getString(WearSync.KEY_FAVOURITES)?.let {
            runCatching { WearSync.json.decodeFromString<List<Favourite>>(it) }.getOrNull()
        }
        val myStations = map.getString(WearSync.KEY_MY_STATIONS)?.let {
            runCatching { WearSync.json.decodeFromString<List<PinnedStation>>(it) }.getOrNull()
        }
        val mode = if (map.containsKey(WearSync.KEY_DEFAULT_MODE)) {
            map.getInt(WearSync.KEY_DEFAULT_MODE)
        } else {
            null
        }

        val current = currentPayload()
        lastReceived = SyncPayload(
            favourites = favourites ?: current.favourites,
            myStations = myStations ?: current.myStations,
            defaultMode = mode ?: current.defaultMode,
        )

        if (favourites != null && favourites != current.favourites) favStore.replaceAll(favourites)
        if (myStations != null && myStations != current.myStations) myStore.replaceAll(myStations)
        if (mode != null && mode != current.defaultMode) prefs.setDefaultMode(TransportMode.fromRaw(mode))
    }

    suspend fun sendTrack(cmd: TrackCommand) {
        val bytes = WearSync.encodeTrack(cmd)
        val nodes = runCatching { nodeClient.connectedNodes.await() }.getOrNull() ?: return
        for (node in nodes) {
            runCatching { messageClient.sendMessage(node.id, WearSync.TRACK_PATH, bytes).await() }
        }
    }

    companion object {
        @Volatile private var instance: WearStateSync? = null

        fun get(context: Context): WearStateSync =
            instance ?: synchronized(this) {
                instance ?: WearStateSync(context.applicationContext).also { instance = it }
            }
    }
}
