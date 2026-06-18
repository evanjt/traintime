package com.evanjt.traintime

import com.evanjt.traintime.core.sync.WearStateSync
import com.evanjt.traintime.core.sync.WearSync
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.runBlocking

// Receives state items pushed by the watch (favourites / pinned stations /
// default mode) and applies them locally. Callbacks run on a background binder
// thread, so blocking on the DataStore writes here is fine. The analog of the
// phone's WCSessionDelegate didReceiveApplicationContext.
class PhoneWearListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        val sync = WearStateSync.get(applicationContext)
        for (event in events) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == WearSync.STATE_PATH
            ) {
                val map = DataMapItem.fromDataItem(event.dataItem).dataMap
                runBlocking { sync.applyReceived(map) }
            }
        }
    }
}
