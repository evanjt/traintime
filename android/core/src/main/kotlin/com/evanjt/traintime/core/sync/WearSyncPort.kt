package com.evanjt.traintime.core.sync

// The slice of WearStateSync a watch-side ViewModel talks to. A seam so the
// Data Layer can be faked in unit tests; WearStateSync is the real transport.
interface WearSyncPort {
    var isWatch: Boolean

    suspend fun pushState()

    suspend fun sendLiveness(kind: String)

    suspend fun connectedWatchNames(): List<String>
}
