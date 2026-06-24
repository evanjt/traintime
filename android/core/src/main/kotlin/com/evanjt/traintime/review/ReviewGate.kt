package com.evanjt.traintime.review

// Decides whether to auto-prompt for a review. Pure so the threshold and the
// once-per-version guard can be unit-tested without a UI.
object ReviewGate {
    const val TRACK_THRESHOLD = 3

    fun shouldPrompt(trackCount: Int, promptedVersion: String, currentVersion: String): Boolean =
        trackCount >= TRACK_THRESHOLD && promptedVersion != currentVersion
}
