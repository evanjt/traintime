package com.evanjt.traintime.ui.adaptive

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.DarkPalette
import com.evanjt.traintime.LightPalette
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.ui.station.DepartureRow
import com.evanjt.traintime.ui.tracking.FormationDiagram
import com.evanjt.traintime.ui.tracking.TrackingBar
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// The split: board on the left, tracking or the hint on the right, on an
// expanded window and on an unfolded book-style foldable.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w840dp-h900dp")
class TwoPaneSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun dep(line: String, dest: String, min: Int, delay: Int = 0) = Departure(
        destination = dest,
        minutesUntil = min,
        departureTimestamp = 1000L,
        delay = delay,
        platform = "3",
        platformChanged = false,
        lineNumber = line,
        category = "IC",
        trainNumber = null,
        operatorRef = null,
    )

    private val formation = Formation(
        track = "3",
        sectors = listOf("A", "B", "C"),
        wagons = listOf(
            FormationWagon(1, 1, 1, "A", listOf("business"), false),
            FormationWagon(2, 2, 2, "B", listOf("restaurant"), false),
            FormationWagon(3, 3, 2, "C", listOf("bike"), false),
        ),
    )

    private val rows = listOf(
        dep("IR15", "Luzern", 6),
        dep("IC8", "Romanshorn", 8, delay = 1),
        dep("S7", "Worb Dorf", 11),
        dep("RE90", "Biel/Bienne", 14),
    )

    // The tracking pane shows the IC8, so its row is the one marked.
    private val trackedIc8 = 1

    @Composable
    private fun board(tracked: Int?) {
        Column {
            rows.forEachIndexed { index, row ->
                DepartureRow(
                    row,
                    isFavourite = row.lineNumber == "S7",
                    mode = TransportMode.TRAIN,
                    selected = index == tracked,
                )
            }
        }
    }

    @Composable
    private fun tracking() {
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("IC8 Romanshorn", style = MaterialTheme.typography.titleLarge)
            Text("8 min", fontSize = 56.sp, fontWeight = FontWeight.Bold)
            TrackingBar(schedBuf = 4.0, effectBuf = 5.0, hasGps = true)
            FormationDiagram(formation)
        }
    }

    private fun capture(
        name: String,
        dark: Boolean,
        fold: VerticalFold? = null,
        tracked: Int? = trackedIc8,
        detail: @Composable () -> Unit,
    ) {
        composeRule.setContent {
            CompositionLocalProvider(LocalAppPalette provides if (dark) DarkPalette else LightPalette) {
                MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                    Surface(Modifier.fillMaxSize()) { TwoPane(board = { board(tracked) }, detail = detail, fold = fold) }
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

    @Test fun splitTrackingLight() = capture("split_tracking_light", dark = false) { tracking() }

    @Test fun splitTrackingDark() = capture("split_tracking_dark", dark = true) { tracking() }

    // The inner display of a book-style foldable unfolded and held upright.
    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun unfoldedBookTrackingLight() = capture("split_unfolded_book_tracking_light", dark = false) { tracking() }

    // A two-screen device whose hinge hides a strip of the window: the board
    // ends at the hinge, tracking starts after it, nothing is drawn under it.
    @Test fun occludingFoldTrackingLight() =
        capture("split_occluding_fold_tracking_light", dark = false, fold = VerticalFold(410f, 430f)) { tracking() }

    // A book-style foldable half-open: the panes meet at the crease.
    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun halfOpenBookTrackingLight() =
        capture("split_half_open_book_tracking_light", dark = false, fold = VerticalFold(337f, 337f)) { tracking() }

    @Test fun theTrackedRowReadsAsSelected() {
        composeRule.setContent {
            CompositionLocalProvider(LocalAppPalette provides LightPalette) {
                MaterialTheme(colorScheme = lightColorScheme()) { board(trackedIc8) }
            }
        }
        composeRule.onAllNodes(isSelected()).assertCountEquals(1)
        composeRule.onNode(isSelected()).assert(hasAnyDescendant(hasText("Romanshorn")))
    }

    @Test fun splitHintLight() = capture("split_hint_light", dark = false, tracked = null) { TrackingPaneHint() }
}
