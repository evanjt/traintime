package com.evanjt.traintime.review

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewGateTest {
    @Test
    fun `below threshold never prompts`() {
        assertFalse(ReviewGate.shouldPrompt(trackCount = 2, promptedVersion = "", currentVersion = "0.5.0"))
    }

    @Test
    fun `at threshold prompts once for a new version`() {
        assertTrue(ReviewGate.shouldPrompt(trackCount = 3, promptedVersion = "", currentVersion = "0.5.0"))
    }

    @Test
    fun `already prompted this version does not prompt again`() {
        assertFalse(ReviewGate.shouldPrompt(trackCount = 9, promptedVersion = "0.5.0", currentVersion = "0.5.0"))
    }

    @Test
    fun `prompts again after a version bump`() {
        assertTrue(ReviewGate.shouldPrompt(trackCount = 9, promptedVersion = "0.4.2", currentVersion = "0.5.0"))
    }
}
