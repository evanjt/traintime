package com.evanjt.traintime.data.api

import com.evanjt.traintime.Timing

// Which host to try first. A failure moves the preference to the next host
// for the rest of the process, and the primary is re-probed once the
// reprobe window has passed. Seconds-based clock for tests.
class HostFailover(
    private val hostCount: Int,
    private val reprobeSeconds: Long = Timing.PRIMARY_REPROBE_SECONDS,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private var preferred = 0
    private var demotedAt = 0L

    // Host indices in the order to attempt them, preferred first, wrapping
    // so every host gets one attempt.
    @Synchronized
    fun order(): List<Int> {
        if (preferred != 0 && clock() - demotedAt >= reprobeSeconds) preferred = 0
        return List(hostCount) { (preferred + it) % hostCount }
    }

    @Synchronized
    fun recordFailure(index: Int) {
        if (index != preferred) return
        preferred = (index + 1) % hostCount
        demotedAt = clock()
    }

    @Synchronized
    fun recordSuccess(index: Int) {
        if (index == preferred) return
        preferred = index
        demotedAt = clock()
    }

    companion object {
        fun shouldFailover(code: Int): Boolean = code == 429 || code >= 500
    }
}
