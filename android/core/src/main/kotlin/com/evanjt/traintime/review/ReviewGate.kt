package com.evanjt.traintime.review

// Decides whether to auto-prompt for a review. Pure so the gates can be
// unit-tested without a UI. The prompt fires only for an engaged user: enough
// tracking sessions, an install old enough to have formed an opinion, no
// active snooze, no permanent opt-out, and at most once per release.
object ReviewGate {
    const val TRACK_THRESHOLD = 3
    const val MIN_AGE_MS = 3L * 24 * 60 * 60 * 1000
    const val SNOOZE_MS = 14L * 24 * 60 * 60 * 1000

    fun shouldPrompt(
        trackCount: Int,
        promptedVersion: String,
        currentVersion: String,
        firstLaunchTs: Long,
        snoozeUntil: Long,
        optedOut: Boolean,
        now: Long,
    ): Boolean = !optedOut &&
        trackCount >= TRACK_THRESHOLD &&
        firstLaunchTs > 0 && now - firstLaunchTs >= MIN_AGE_MS &&
        now >= snoozeUntil &&
        promptedVersion != currentVersion
}
