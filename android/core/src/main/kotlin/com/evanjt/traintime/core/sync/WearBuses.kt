package com.evanjt.traintime.core.sync

import kotlinx.coroutines.flow.MutableSharedFlow

// Process-wide hand-off from the WearableListenerServices (background binder
// threads, no ViewModel access) to whichever ViewModel is running. If nothing
// collects — the app UI isn't up — the emission is dropped, which is the
// wanted semantic: mirror traffic must not wake a closed app.

// Phone side: liveness kinds (hello / alive / bye / reqLoc) announced by the watch.
object WearLivenessBus {
    val events = MutableSharedFlow<String>(extraBufferCapacity = 8)
}

// Watch side: mirror commands (mode / station / loc / back) pushed by the phone.
object WearCommandBus {
    val events = MutableSharedFlow<WearCommand>(extraBufferCapacity = 8)
}
