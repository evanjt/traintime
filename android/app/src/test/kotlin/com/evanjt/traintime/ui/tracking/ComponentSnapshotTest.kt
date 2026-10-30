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
            FormationWagon(1, 1, 1, "A", listOf("business"), false, mixedClass = true),
            FormationWagon(2, 2, 2, "B", listOf("wheelchair", "restaurant"), false),
            FormationWagon(3, 3, 2, "C", listOf("wifi"), false),
            FormationWagon(4, 4, 2, "C", listOf("bike"), true),
        ),
    )

    // A 16-car double unit as the feed gives it at the boarding stop, front first,
    // with no passage between the two units after car 11.
    private val doubleUnit = Formation(
        track = "7",
        sectors = listOf("H", "G", "F", "E", "D", "C", "B", "A"),
        wagons = listOf(
            car(18, 2, "H", "family", "low_floor"),
            car(17, 2, "H", "low_floor", "bike"),
            car(16, 2, "G", "low_floor", "bike"),
            car(15, 2, "G", "wheelchair", "low_floor"),
            car(14, 2, "F", "wheelchair", "low_floor"),
            car(13, 1, "F", "low_floor", "bike"),
            car(12, 1, "E", "low_floor", "bike"),
            car(11, 1, "E", "business", "low_floor", "bike", noPassageAfter = true),
            car(8, 2, "D", "family", "low_floor"),
            car(7, 2, "D", "low_floor", "bike"),
            car(6, 2, "C", "low_floor", "bike"),
            car(5, 2, "B", "wheelchair", "low_floor"),
            car(4, 2, "B", "wheelchair", "restaurant", "low_floor"),
            car(3, 1, "B", "low_floor", "bike"),
            car(2, 1, "A", "low_floor", "bike"),
            car(1, 1, "A", "business", "low_floor", "bike"),
        ).mapIndexed { i, w -> w.copy(position = i + 1) },
    )

    // An S-Bahn of two four-car units whose cars the feed does not number, live at Bern
    private val unnumbered = Formation(
        track = "13",
        sectors = listOf("A", "B", "C", "D", "E", "F"),
        wagons = listOf(
            car(null, 2, "A", "low_floor"),
            car(null, 2, "A", "wheelchair", "low_floor", "bike"),
            car(null, 1, "A", "low_floor", "bike").copy(mixedClass = true),
            car(null, 2, "A", "low_floor", noPassageAfter = true),
            car(null, 2, "A", "low_floor"),
            car(null, 2, "A", "wheelchair", "low_floor", "bike"),
            car(null, 1, "B", "low_floor", "bike").copy(mixedClass = true),
            car(null, 2, "B", "low_floor"),
        ).mapIndexed { i, w -> w.copy(position = i + 1) },
    )

    private fun car(number: Int?, wagonClass: Int, sector: String, vararg features: String, noPassageAfter: Boolean = false) =
        FormationWagon(0, number, wagonClass, sector, features.toList(), false, noPassageAfter = noPassageAfter)

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

    @Test fun formationLight() = capture("formation_light", dark = false) {
        Box(Modifier.width(360.dp).padding(16.dp)) { FormationDiagram(doubleUnit) }
    }

    @Test fun formationDark() = capture("formation_dark", dark = true) {
        Box(Modifier.width(360.dp).padding(16.dp)) { FormationDiagram(doubleUnit) }
    }

    @Test fun formationUnnumbered() = capture("formation_unnumbered", dark = false) {
        Box(Modifier.width(360.dp).padding(16.dp)) { FormationDiagram(unnumbered) }
    }

    @Test fun pausedLight() = capture("paused_light", dark = false) { Box(Modifier.size(320.dp, 220.dp)) { InactiveScreen {} } }

    @Test fun pausedDark() = capture("paused_dark", dark = true) { Box(Modifier.size(320.dp, 220.dp)) { InactiveScreen {} } }
}
