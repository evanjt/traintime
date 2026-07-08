package com.evanjt.traintime.notify

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.evanjt.traintime.GarminConnectIQService
import com.evanjt.traintime.core.sync.TrackCommand
import com.evanjt.traintime.data.prefs.PendingRouteStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// Handles the reminder's "Send to Watch" action, relayed from a paired Garmin.
// The user picks the action on the watch, Android runs this PendingIntent on the
// phone, and we wake the TrainTime watch app over the Connect IQ bridge and push
// the saved route's current leg into tracking. No watch-side change: the Garmin
// app already consumes {"action":"track", ...} in handlePhoneMessage.
class SendToWatchReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_ROUTE_ID = "route_id"

        // Kept under the ~10 s BroadcastReceiver background window. If the
        // ConnectIQ init+open+send chain proves to exceed it on-device, escalate
        // this to a shortService foreground service (Android 14+).
        private const val OVERALL_TIMEOUT_MS = 9_000L
        private const val SDK_READY_TIMEOUT_MS = 2_500L
        private const val HELLO_WAIT_MS = 3_500L
        private const val RETRY_DELAY_MS = 2_000L

        // Separate id so a failure toast doesn't clobber the reminder itself.
        private val REACH_FAIL_NOTIF_ID = PendingRouteNotifier.NOTIF_ID + 1
    }

    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        val appContext = context.applicationContext
        // Main dispatcher: the Connect IQ SDK binds and delivers its callbacks on
        // the main looper, matching the ViewModel's use of the service.
        CoroutineScope(Dispatchers.Main).launch {
            try {
                withTimeoutOrNull(OVERALL_TIMEOUT_MS) { sendToWatch(appContext) }
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun sendToWatch(context: Context) {
        val route = PendingRouteStore(context).current() ?: return
        val leg = route.currentLeg ?: return
        val payload = TrackCommand.fromLeg(leg, route.finalDestination).toGarminMap()

        val service = GarminConnectIQService(context)
        try {
            // Any non-bye message proves the watch app is up and registered for
            // phone messages: a track sent before that is silently dropped.
            val watchReady = CompletableDeferred<Unit>()
            service.onMessageReceived = { ctx ->
                if (ctx["kind"] != "bye" && !watchReady.isCompleted) watchReady.complete(Unit)
            }
            service.initialize()
            if (!awaitSdkReady(service)) return

            val devices = service.eligibleDevices()
            if (devices.isEmpty()) {
                notifyUnreachable(context)
                return
            }

            devices.forEach { service.openApp(it.id) }
            // Send on the watch's hello when it arrives; otherwise fall back after
            // a short wait, then retry once to cover a send that raced the cold
            // start (the watch app registering after openApp but before our send).
            withTimeoutOrNull(HELLO_WAIT_MS) { watchReady.await() }
            devices.forEach { service.send(it.id, payload) }
            delay(RETRY_DELAY_MS)
            devices.forEach { service.send(it.id, payload) }
        } finally {
            service.shutdown()
        }
    }

    // The SDK binds asynchronously (isAvailable flips on onSdkReady); poll briefly
    // before querying devices so we don't read an empty list from an unbound SDK.
    private suspend fun awaitSdkReady(service: GarminConnectIQService): Boolean {
        var waited = 0L
        while (!service.isAvailable && waited < SDK_READY_TIMEOUT_MS) {
            delay(100)
            waited += 100
        }
        return service.isAvailable
    }

    private fun notifyUnreachable(context: Context) {
        PendingRouteNotifier.ensureChannel(context)
        val notification = NotificationCompat.Builder(context, PendingRouteNotifier.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Couldn't reach watch")
            .setContentText("Open TrainTime on your watch and try again.")
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(REACH_FAIL_NOTIF_ID, notification)
    }
}
