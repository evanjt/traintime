package com.evanjt.traintime.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
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

// Visual regression for the walkthrough's widget look-alike (the Compose replica
// of the Glance widget shown in the tour's final step) in light and dark, driven
// through the manual appearance override. Renders on the JVM via Robolectric.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class OnboardingSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun capture(name: String, mode: String) {
        composeRule.setContent {
            TrainTimeTheme(appearanceMode = mode) {
                Box(Modifier.background(MaterialTheme.colorScheme.background).padding(16.dp)) {
                    TourWidgetMock()
                }
            }
        }
        composeRule.onRoot().captureRoboImage("src/test/screenshots/$name.png", roborazziOptions = TOLERANT)
    }

    private companion object {
        val TOLERANT = RoborazziOptions(
            compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0.01f),
        )
    }

    private fun captureWatch(name: String, mode: String) {
        composeRule.setContent {
            TrainTimeTheme(appearanceMode = mode) {
                // 700 dp tall: the 2+1 tile layout is taller than the old pair.
                Box(Modifier.size(411.dp, 700.dp).background(MaterialTheme.colorScheme.background)) {
                    TourWatchSurface(topInset = 0.dp, onReport = {})
                }
            }
        }
        composeRule.onRoot().captureRoboImage("src/test/screenshots/$name.png", roborazziOptions = TOLERANT)
    }

    @Test
    fun tourWidgetLight() = capture("tour_widget_light", mode = "light")

    @Test
    fun tourWidgetDark() = capture("tour_widget_dark", mode = "dark")

    @Test
    @Config(qualifiers = "+h800dp")
    fun tourWatchLight() = captureWatch("tour_watch_light", mode = "light")

    @Test
    @Config(qualifiers = "+h800dp")
    fun tourWatchDark() = captureWatch("tour_watch_dark", mode = "dark")
}
