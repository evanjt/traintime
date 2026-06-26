package com.evanjt.traintime.ui.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.ui.theme.TrainTimeTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// Visual regression for the first-launch onboarding carousel (first card) in light
// and dark, driving the theme through the manual appearance override path. Renders
// on the JVM via Robolectric — no emulator. A fixed box size keeps goldens stable.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class OnboardingSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun capture(name: String, mode: String) {
        composeRule.setContent {
            TrainTimeTheme(appearanceMode = mode) {
                Box(Modifier.size(411.dp, 891.dp)) {
                    OnboardingScreen(onComplete = {})
                }
            }
        }
        composeRule.onRoot().captureRoboImage("src/test/screenshots/$name.png", roborazziOptions = TOLERANT)
    }

    private companion object {
        // Absorb minor anti-aliasing differences between local and CI rendering.
        val TOLERANT = RoborazziOptions(
            compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0.01f),
        )
    }

    @Test
    fun onboardingLight() = capture("onboarding_light", mode = "light")

    @Test
    fun onboardingDark() = capture("onboarding_dark", mode = "dark")
}
