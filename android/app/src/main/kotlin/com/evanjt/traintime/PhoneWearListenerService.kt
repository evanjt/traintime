package com.evanjt.traintime

import com.evanjt.traintime.core.sync.WearLivenessBus
import com.evanjt.traintime.core.sync.WearStateSync
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.notify.PendingRouteNotifier
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.runBlocking

// Receives state items pushed by the watch (favourites / pinned stations /
// default mode) and applies them locally. Callbacks run on a background binder
// thread, so blocking on the DataStore writes here is fine. The analog of the
// phone's WCSessionDelegate didReceiveApplicationContext. Liveness kinds
// (hello / alive / bye / reqLoc) arrive as messages and are handed to the
// running ViewModel over the bus, dropped when the app UI isn't up.
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

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            WearSync.LIVENESS_PATH ->
                WearLivenessBus.events.tryEmit(event.data.toString(Charsets.UTF_8))
            // The watch asked us to save its focused departure as a reminder.
            // Schedule directly so it works with the app closed; the VM's
            // pending-route collector picks up the store write when the app is up.
            WearSync.REMINDER_PATH -> {
                val cmd = WearSync.decodeReminder(event.data) ?: return
                runBlocking {
                    PendingRouteNotifier.saveAndSchedule(
                        applicationContext,
                        cmd.toRoute(),
                        System.currentTimeMillis() / 1000,
                    )
                }
            }
        }
    }
}
