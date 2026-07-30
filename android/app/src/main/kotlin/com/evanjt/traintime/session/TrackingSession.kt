package com.evanjt.traintime.session

import com.evanjt.traintime.data.model.FocusedDeparture
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow

// Everything the tracking notification renders. Built by the ViewModel while
// the app is foreground (its 10 s fetch is fresher) and by the service's own
// loop while backgrounded, so both paths feed one renderer.
data class TrackingSnapshot(
    val focused: FocusedDeparture,
    val stationId: String?,
    val stationName: String?,
    val stationLat: Double?,
    val stationLon: Double?,
    val walkDistMeters: Double?,
    val gpsOk: Boolean,
)


// Process-local link between MainViewModel and TrackingNotificationService.
// Both live in this process, so flows beat intents for everything except the
// service's own start/stop lifecycle.
object TrackingSessionBus {
    // Set from the VM's onAppear/onDisappear. The service's loop stays idle
    // while the app is foreground (the VM fetches and pushes instead), and
    // takes over the moment this drops to false.
    val appForeground = MutableStateFlow(false)

    // VM -> service: freshest snapshot to render while foreground.
    val vmPush = MutableSharedFlow<TrackingSnapshot>(extraBufferCapacity = 1)

    // Service -> VM: the notification's "Stop tracking" action. The VM exits
    // tracking so a reopened app doesn't resurrect the session.
    val stopRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
}
