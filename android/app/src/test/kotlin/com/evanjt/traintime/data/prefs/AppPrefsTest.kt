package com.evanjt.traintime.data.prefs

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

// Round-trips the 0.5.0 accessors through the real DataStore. One method keeps
// the shared process-wide store from leaking writes between tests: defaults are
// read before any write, then each writer is verified against its own value.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppPrefsTest {
    private val prefs = AppPrefs(RuntimeEnvironment.getApplication())

    @Test
    fun `onboarding appearance and review prefs round-trip`() = runTest {
        assertFalse(prefs.hasSeenOnboarding.first())
        assertEquals("system", prefs.appearanceMode.first())
        assertEquals(0, prefs.reviewTrackCount.first())
        assertEquals("", prefs.reviewPromptedVersion.first())

        prefs.markOnboardingSeen()
        assertTrue(prefs.hasSeenOnboarding.first())

        prefs.setAppearanceMode("dark")
        assertEquals("dark", prefs.appearanceMode.first())

        prefs.incrementReviewTrackCount()
        prefs.incrementReviewTrackCount()
        assertEquals(2, prefs.reviewTrackCount.first())

        prefs.setReviewPromptedVersion("0.5.0")
        assertEquals("0.5.0", prefs.reviewPromptedVersion.first())
    }
}
