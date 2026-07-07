package com.evanjt.traintime.core.sync

// The slice of WearStateSync a watch-side ViewModel talks to. A seam so the
// Data Layer can be faked in unit tests; WearStateSync is the real transport.
interface WearSyncPort {
    var isWatch: Boolean

    suspend fun pushState()

    suspend fun sendLiveness(kind: String)

    // Watch -> phone: ask the phone to save the focused departure as a reminder.
    // Returns whether it reached a connected phone.
    suspend fun sendReminder(cmd: ReminderCommand): Boolean

    suspend fun connectedWatchNames(): List<String>

    // Nodes that actually have the Wear app installed (declare the capability),
    // for the phone's Send-to-Watch list. A superset check of connectedWatchNames.
    suspend fun appInstalledWatchNames(): List<String>
}
