package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.DarkPalette
import com.evanjt.traintime.LightPalette
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import com.evanjt.traintime.ui.station.InactiveScreen
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// Visual regression for the tracking bar (ahead/behind/on-time/no-GPS), the
// formation diagram (1st/2nd class, sectors, features) and the Paused screen,
// in light and dark.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ComponentSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val formation = Formation(
        track = "3",
        sectors = listOf("A", "B", "C"),
        wagons = listOf(
            FormationWagon(1, 1, 1, "A", listOf("business"), false),
            FormationWagon(2, 2, 2, "B", listOf("wheelchair", "restaurant"), false),
            FormationWagon(3, 3, 2, "C", emptyList(), false),
        ),
    )

    @Composable
    private fun tracking() {
        Column(
            Modifier.width(360.dp).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TrackingBar(schedBuf = 4.0, effectBuf = 5.0, hasGps = true)
            TrackingBar(schedBuf = -2.0, effectBuf = -1.0, hasGps = true)
            TrackingBar(schedBuf = 0.0, effectBuf = 0.0, hasGps = true)
            TrackingBar(schedBuf = 0.0, effectBuf = 0.0, hasGps = false)
            FormationDiagram(formation)
        }
    }

    private fun capture(name: String, dark: Boolean, content: @Composable () -> Unit) {
        composeRule.setContent {
            CompositionLocalProvider(LocalAppPalette provides if (dark) DarkPalette else LightPalette) {
                MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                    Surface { content() }
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

    @Test fun trackingLight() = capture("tracking_light", dark = false) { tracking() }

    @Test fun trackingDark() = capture("tracking_dark", dark = true) { tracking() }

    @Test fun pausedLight() = capture("paused_light", dark = false) { Box(Modifier.size(320.dp, 220.dp)) { InactiveScreen {} } }

    @Test fun pausedDark() = capture("paused_dark", dark = true) { Box(Modifier.size(320.dp, 220.dp)) { InactiveScreen {} } }
}
