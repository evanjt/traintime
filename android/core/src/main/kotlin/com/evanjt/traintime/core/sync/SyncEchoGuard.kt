package com.evanjt.traintime.core.sync

// Decides whether a locally observed payload needs pushing. Remembers what was
// last sent and last received so an applied remote change doesn't bounce
// straight back over the Data Layer. Pure state, no GMS, unit-testable.
class SyncEchoGuard<T> {
    @Volatile private var lastSent: T? = null
    @Volatile private var lastReceived: T? = null

    fun shouldPush(payload: T): Boolean = payload != lastSent && payload != lastReceived

    fun noteSent(payload: T) {
        lastSent = payload
    }

    fun noteReceived(payload: T) {
        lastReceived = payload
    }
}
