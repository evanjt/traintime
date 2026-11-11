package com.evanjt.traintime.ui.adaptive

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
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
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.ui.station.DepartureRow
import com.evanjt.traintime.ui.tracking.FormationDiagram
import com.evanjt.traintime.ui.tracking.TrackingBar
import com.evanjt.traintime.ui.tracking.TrackingPeekSummary
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// The wide-window layouts as the layout decision draws them: side by side,
// the tracking card at each stop on an opened book-style foldable, and the
// single pane on a landscape phone too short for a second one.
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
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("IC8 Romanshorn", style = MaterialTheme.typography.titleLarge)
            Text("8 min", fontSize = 56.sp, fontWeight = FontWeight.Bold)
            TrackingBar(schedBuf = 4.0, effectBuf = 5.0, hasGps = true)
            FormationDiagram(formation)
        }
    }

    private val focusedIc8 = FocusedDeparture(
        destination = "Romanshorn",
        departureTimestamp = 1_800_000_480L,
        lineNumber = "IC8",
        category = "IC",
        trainNumber = null,
        operatorRef = null,
        delay = 1,
        platform = "3",
        platformChanged = false,
    )

    @Composable
    private fun peek() = TrackingPeekSummary(focusedIc8, TransportMode.TRAIN, nowSeconds = 1_800_000_000L)

    @Composable
    private fun panes(
        dark: Boolean,
        fold: VerticalFold?,
        tracked: Int?,
        stop: CardStop,
        onStopChange: (CardStop) -> Unit = {},
        detail: @Composable () -> Unit,
    ) {
        CompositionLocalProvider(LocalAppPalette provides if (dark) DarkPalette else LightPalette) {
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) {
                    BoxWithConstraints {
                        AdaptivePanes(
                            widthDp = maxWidth.value,
                            heightDp = maxHeight.value,
                            fold = fold,
                            appState = if (tracked != null) 2 else 0,
                            stop = stop,
                            onStopChange = onStopChange,
                            onStopTracking = {},
                            board = { board(tracked) },
                            tracking = { detail() },
                            peek = { peek() },
                            hint = detail,
                        )
                    }
                }
            }
        }
    }

    private fun capture(
        name: String,
        dark: Boolean,
        fold: VerticalFold? = null,
        tracked: Int? = trackedIc8,
        stop: CardStop = CardStop.HALF,
        detail: @Composable () -> Unit,
    ) {
        composeRule.setContent { panes(dark, fold, tracked, stop, detail = detail) }
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

    // A two-screen device whose hinge hides a strip of the window: the board
    // ends at the hinge, tracking starts after it, nothing is drawn under it.
    @Test fun occludingFoldTrackingLight() =
        capture("split_occluding_fold_tracking_light", dark = false, fold = VerticalFold(410f, 430f)) { tracking() }

    // The inner display of a book-style foldable opened: card mode.
    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun cardPeekIdleLight() = capture("card_674_peek_idle_light", dark = false, tracked = null) { TrackingPaneHint() }

    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun cardPeekTrackingLight() = capture("card_674_peek_tracking_light", dark = false, stop = CardStop.PEEK) { tracking() }

    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun cardHalfLight() = capture("card_674_half_light", dark = false) { tracking() }

    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun cardHalfOnTheCreaseLight() =
        capture("card_674_half_crease_light", dark = false, fold = VerticalFold(337f, 337f)) { tracking() }

    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun cardFullLight() = capture("card_674_full_light", dark = false, stop = CardStop.FULL) { tracking() }

    // The iPhone Duo's inner display opened like a book, and a landscape tablet.
    @Config(sdk = [34], qualifiers = "w951dp-h669dp")
    @Test fun sideBySide951Light() = capture("side_by_side_951_tracking_light", dark = false) { tracking() }

    @Config(sdk = [34], qualifiers = "w1280dp-h800dp")
    @Test fun sideBySide1280Light() = capture("side_by_side_1280_tracking_light", dark = false) { tracking() }

    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun theGrabberOpensAndClosesAStop() {
        var stop by mutableStateOf(CardStop.HALF)
        composeRule.setContent { panes(false, null, trackedIc8, stop, onStopChange = { stop = it }) { tracking() } }
        composeRule.onNodeWithTag(CARD_GRABBER_TAG).performSemanticsAction(SemanticsActions.Expand)
        composeRule.waitForIdle()
        assertEquals(CardStop.FULL, stop)
        composeRule.onNodeWithTag(CARD_GRABBER_TAG).performSemanticsAction(SemanticsActions.Collapse)
        composeRule.onNodeWithTag(CARD_GRABBER_TAG).performSemanticsAction(SemanticsActions.Collapse)
        composeRule.waitForIdle()
        assertEquals(CardStop.PEEK, stop)
        composeRule.onNodeWithTag(CARD_GRABBER_TAG).assert(SemanticsMatcher.keyNotDefined(SemanticsActions.Collapse))
    }

    @Config(sdk = [34], qualifiers = "w674dp-h841dp")
    @Test fun aDragOnTheGrabberSettlesOnAStop() {
        var stop by mutableStateOf(CardStop.HALF)
        composeRule.setContent { panes(false, null, trackedIc8, stop, onStopChange = { stop = it }) { tracking() } }
        composeRule.onNodeWithTag(CARD_GRABBER_TAG).performTouchInput { swipeLeft(startX = centerX, endX = centerX - 600f) }
        composeRule.waitForIdle()
        assertEquals(CardStop.FULL, stop)
    }

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

    // The folded iPhone Duo's size and a large phone turned sideways: too short
    // for a second pane, so the board and tracking each take the window.
    @Config(sdk = [34], qualifiers = "w678dp-h466dp")
    @Test fun shortLandscapeBoardLight() = capture("short_landscape_678_board_light", dark = false, tracked = null) {}

    @Config(sdk = [34], qualifiers = "w678dp-h466dp")
    @Test fun shortLandscapeTrackingLight() = capture("short_landscape_678_tracking_light", dark = false) { tracking() }

    @Config(sdk = [34], qualifiers = "w956dp-h440dp")
    @Test fun wideShortLandscapeBoardLight() = capture("short_landscape_956_board_light", dark = false, tracked = null) {}

    @Config(sdk = [34], qualifiers = "w956dp-h440dp")
    @Test fun wideShortLandscapeTrackingLight() = capture("short_landscape_956_tracking_light", dark = false) { tracking() }
}
