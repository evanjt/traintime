package com.evanjt.traintime.review

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewGateTest {
    private val now = 1_000_000_000_000L
    private val oldEnough = now - ReviewGate.MIN_AGE_MS

    private fun prompt(
        trackCount: Int = 3,
        promptedVersion: String = "",
        currentVersion: String = "0.5.0",
        firstLaunchTs: Long = oldEnough,
        snoozeUntil: Long = 0L,
        optedOut: Boolean = false,
    ) = ReviewGate.shouldPrompt(
        trackCount, promptedVersion, currentVersion,
        firstLaunchTs, snoozeUntil, optedOut, now,
    )

    @Test
    fun `below threshold never prompts`() {
        assertFalse(prompt(trackCount = 2))
    }

    @Test
    fun `at threshold prompts once for a new version`() {
        assertTrue(prompt(trackCount = 3))
    }

    @Test
    fun `already prompted this version does not prompt again`() {
        assertFalse(prompt(trackCount = 9, promptedVersion = "0.5.0"))
    }

    @Test
    fun `prompts again after a version bump`() {
        assertTrue(prompt(trackCount = 9, promptedVersion = "0.4.2"))
    }

    @Test
    fun `install younger than the minimum age does not prompt`() {
        assertFalse(prompt(firstLaunchTs = oldEnough + 1))
    }

    @Test
    fun `install exactly at the minimum age prompts`() {
        assertTrue(prompt(firstLaunchTs = oldEnough))
    }

    @Test
    fun `missing first-launch timestamp never prompts`() {
        assertFalse(prompt(firstLaunchTs = 0L))
    }

    @Test
    fun `active snooze does not prompt`() {
        assertFalse(prompt(snoozeUntil = now + 1))
    }

    @Test
    fun `expired snooze prompts`() {
        assertTrue(prompt(snoozeUntil = now))
    }

    @Test
    fun `opt-out wins over everything`() {
        assertFalse(prompt(trackCount = 99, optedOut = true))
    }
}
