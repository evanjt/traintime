package com.evanjt.traintime.core.sync

import android.content.Context
import com.evanjt.traintime.data.model.Favourite
import com.evanjt.traintime.data.model.PinnedStation
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.prefs.MyStationsStore
import com.evanjt.traintime.data.prefs.PendingRouteStore
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
    val pendingRoute: PendingRoute? = null,
)

// Bidirectional favourites / pinned-stations / default-mode sync over the
// Wearable Data Layer. The Android analog of WCSession updateApplicationContext.
// Track commands go over MessageClient (sendTrack), like PhoneWatchService.
//
// A process-wide singleton so the running ViewModel (which pushes on local
// edits) and the WearableListenerService (which applies remote edits) share one
// echo-guard: a push is skipped when its content matches what we last sent or
// last received, so an applied remote change doesn't bounce straight back.
class WearStateSync private constructor(context: Context) : WearSyncPort {
    private val appContext = context.applicationContext
    private val favStore = FavouritesStore(appContext)
    private val myStore = MyStationsStore(appContext)
    private val prefs = AppPrefs(appContext)
    private val pendingStore = PendingRouteStore(appContext)

    // The pending route is phone-owned: only the phone publishes it, only the
    // watch applies it. Watch entry points (listener service, ViewModel) set
    // this before any sync work.
    @Volatile override var isWatch = false

    private val dataClient = Wearable.getDataClient(appContext)
    private val messageClient = Wearable.getMessageClient(appContext)
    private val nodeClient = Wearable.getNodeClient(appContext)

    private val echoGuard = SyncEchoGuard<SyncPayload>()

    private suspend fun currentPayload(): SyncPayload = SyncPayload(
        favourites = favStore.all(),
        myStations = myStore.all(),
        defaultMode = prefs.defaultModeNow().raw,
        pendingRoute = pendingStore.current(),
    )

    override suspend fun pushState() {
        val payload = currentPayload()
        if (!echoGuard.shouldPush(payload)) return
        val request = PutDataMapRequest.create(WearSync.STATE_PATH).apply {
            dataMap.putString(WearSync.KEY_FAVOURITES, WearSync.json.encodeToString(payload.favourites))
            dataMap.putString(WearSync.KEY_MY_STATIONS, WearSync.json.encodeToString(payload.myStations))
            dataMap.putInt(WearSync.KEY_DEFAULT_MODE, payload.defaultMode)
            if (!isWatch) {
                payload.pendingRoute?.let {
                    dataMap.putString(WearSync.KEY_PENDING_ROUTE, WearSync.json.encodeToString(it))
                }
            }
        }.asPutDataRequest().setUrgent()
        runCatching { dataClient.putDataItem(request).await() }
        echoGuard.noteSent(payload)
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

        // Pending route: watch applies (absent key = phone cleared it); the
        // phone never accepts it back.
        val pendingRoute = if (isWatch) {
            map.getString(WearSync.KEY_PENDING_ROUTE)?.let {
                runCatching { WearSync.json.decodeFromString<PendingRoute>(it) }.getOrNull()
            }
        } else {
            null
        }

        val current = currentPayload()
        echoGuard.noteReceived(
            SyncPayload(
                favourites = favourites ?: current.favourites,
                myStations = myStations ?: current.myStations,
                defaultMode = mode ?: current.defaultMode,
                pendingRoute = if (isWatch) pendingRoute else current.pendingRoute,
            ),
        )

        if (favourites != null && favourites != current.favourites) favStore.replaceAll(favourites)
        if (myStations != null && myStations != current.myStations) myStore.replaceAll(myStations)
        if (mode != null && mode != current.defaultMode) prefs.setDefaultMode(TransportMode.fromRaw(mode))
        if (isWatch && pendingRoute != current.pendingRoute) pendingStore.replaceFromSync(pendingRoute)
    }

    // Display names of connected watches, for the phone's "Send to Watch" UI.
    override suspend fun connectedWatchNames(): List<String> =
        runCatching { nodeClient.connectedNodes.await().map { it.displayName } }.getOrDefault(emptyList())

    // Watch -> phone liveness announcement (hello / alive / bye / reqLoc).
    // Fire-and-forget to every connected node; a phoneless watch is a silent
    // no-op, matching WatchPhoneSync on the Apple side.
    override suspend fun sendLiveness(kind: String) {
        val bytes = kind.toByteArray(Charsets.UTF_8)
        val nodes = runCatching { nodeClient.connectedNodes.await() }.getOrNull() ?: return
        for (node in nodes) {
            runCatching { messageClient.sendMessage(node.id, WearSync.LIVENESS_PATH, bytes).await() }
        }
    }

    // Phone -> watch mirror command (mode / station / loc / back).
    suspend fun sendCommand(cmd: WearCommand) {
        val bytes = WearSync.encodeCommand(cmd)
        val nodes = runCatching { nodeClient.connectedNodes.await() }.getOrNull() ?: return
        for (node in nodes) {
            runCatching { messageClient.sendMessage(node.id, WearSync.CMD_PATH, bytes).await() }
        }
    }

    // Send the track command to every connected watch; returns how many it reached.
    suspend fun sendTrack(cmd: TrackCommand): Int {
        val bytes = WearSync.encodeTrack(cmd)
        val nodes = runCatching { nodeClient.connectedNodes.await() }.getOrNull() ?: return 0
        var sent = 0
        for (node in nodes) {
            val ok = runCatching { messageClient.sendMessage(node.id, WearSync.TRACK_PATH, bytes).await() }.isSuccess
            if (ok) sent += 1
        }
        return sent
    }

    companion object {
        @Volatile private var instance: WearStateSync? = null

        fun get(context: Context): WearStateSync =
            instance ?: synchronized(this) {
                instance ?: WearStateSync(context.applicationContext).also { instance = it }
            }
    }
}
