package com.evanjt.traintime.wear

import android.content.Intent
import com.evanjt.traintime.core.sync.WearCommandBus
import com.evanjt.traintime.core.sync.WearStateSync
import com.evanjt.traintime.core.sync.WearSync
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.runBlocking

// Watch side of the Data Layer. Applies state pushed by the phone (favourites /
// pinned stations / default mode) and, on a track command, launches the app
// straight into tracking, the analog of the Apple watch's didReceiveMessage,
// which wakes a closed watch app.
class WatchWearListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        val sync = WearStateSync.get(applicationContext)
        sync.isWatch = true
        for (event in events) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == WearSync.STATE_PATH
            ) {
                val map = DataMapItem.fromDataItem(event.dataItem).dataMap
                runBlocking { sync.applyReceived(map) }
            }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            WearSync.TRACK_PATH -> {
                val cmd = WearSync.decodeTrack(event.data) ?: return
                val intent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra(MainActivity.EXTRA_TRACK, WearSync.encodeTrackString(cmd))
                }
                startActivity(intent)
            }
            // Mirror commands never wake the app: if no ViewModel is collecting,
            // the emission is dropped (Apple parity: mirror() sends only when
            // the watch app is reachable).
            WearSync.CMD_PATH -> {
                WearSync.decodeCommand(event.data)?.let { WearCommandBus.events.tryEmit(it) }
            }
        }
    }
}
