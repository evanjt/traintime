package com.evanjt.traintime.ui.adaptive

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture

enum class WidthClass { COMPACT, MEDIUM, EXPANDED }

enum class PaneLayout { BOARD, TRACKING, SPLIT_TRACKING, SPLIT_HINT }

// Material window size class breakpoints, read from the window width in dp.
fun widthClassOf(widthDp: Float): WidthClass = when {
    widthDp < 600f -> WidthClass.COMPACT
    widthDp < 840f -> WidthClass.MEDIUM
    else -> WidthClass.EXPANDED
}

// The space the app draws in, and whether the window crosses a hinge or fold.
data class WindowShape(val widthDp: Float, val heightDp: Float, val hasFold: Boolean)

// An expanded window has room for the board beside tracking. A medium window
// does too when it is at least as wide as it is tall, or when it spans a fold,
// which is how an unfolded book-style foldable is held upright. A medium
// portrait window with no fold (a tablet in split screen) keeps the board, then
// tracking full-screen, as does every compact window. State 3 (inactive) shows
// the board with its scrim either way.
fun paneLayout(shape: WindowShape, appState: Int): PaneLayout {
    val split = when (widthClassOf(shape.widthDp)) {
        WidthClass.EXPANDED -> true
        WidthClass.MEDIUM -> shape.widthDp >= shape.heightDp || shape.hasFold
        WidthClass.COMPACT -> false
    }
    return when {
        split && appState == 2 -> PaneLayout.SPLIT_TRACKING
        split -> PaneLayout.SPLIT_HINT
        appState == 2 -> PaneLayout.TRACKING
        else -> PaneLayout.BOARD
    }
}

// The tracking poll, walk distance and train match all read the board's
// station and mode, so the board must not move away while a train is tracked.
fun boardPickersLocked(appState: Int): Boolean = appState == 2

// A board row is the tracked journey when it leaves at the tracked scheduled
// time and carries the same train number. Without a train number on both, the
// destination decides. Twins in one minute differ only by train number.
fun isTrackedJourney(dep: Departure, focused: FocusedDeparture): Boolean {
    if (dep.departureTimestamp != focused.departureTimestamp) return false
    val depTrain = dep.trainNumber
    val focusedTrain = focused.trainNumber
    if (depTrain != null && focusedTrain != null) return depTrain == focusedTrain
    return dep.destination == focused.destination
}

// Re-tapping the tracked row on a split board must not restart the session.
fun isAlreadyTracked(dep: Departure, appState: Int, focused: FocusedDeparture?): Boolean =
    appState == 2 && focused != null && isTrackedJourney(dep, focused)

// The row the board marks as tracked. Only state 2 has a session, and only a
// split window shows the board beside it.
fun trackedRowIndex(rows: List<Departure>, appState: Int, focused: FocusedDeparture?): Int? =
    rows.indexOfFirst { isAlreadyTracked(it, appState, focused) }.takeIf { it >= 0 }

// A readable board column; tracking takes the rest of the window.
val BOARD_PANE_WIDTH = 400.dp

// A vertical fold or hinge across the split, in dp from the split's left edge.
// A hinge that hides no pixels has start == end.
data class VerticalFold(val startDp: Float, val endDp: Float)

data class PaneSplit(val boardDp: Float, val detailStartDp: Float, val onFold: Boolean)

// With a fold, the board takes everything left of it and tracking everything
// right of it, so neither pane runs across the crease or under an occluded
// strip. Without one, the board keeps its readable width.
fun paneSplit(widthDp: Float, fold: VerticalFold?): PaneSplit {
    val board = BOARD_PANE_WIDTH.value
    if (fold == null || fold.startDp <= 0f || fold.endDp >= widthDp) return PaneSplit(board, board, onFold = false)
    return PaneSplit(fold.startDp, fold.endDp, onFold = true)
}

@Composable
fun TwoPane(
    board: @Composable () -> Unit,
    detail: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    fold: VerticalFold? = null,
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val split = paneSplit(maxWidth.value, fold)
        Row(Modifier.fillMaxSize()) {
            Box(Modifier.width(split.boardDp.dp).fillMaxHeight()) { board() }
            // The fold itself separates the panes, and nothing is drawn under
            // an occluded strip, so only a window without a fold gets a divider.
            if (split.onFold) {
                Spacer(Modifier.width((split.detailStartDp - split.boardDp).dp))
            } else {
                VerticalDivider()
            }
            Box(Modifier.weight(1f).fillMaxHeight()) { detail() }
        }
    }
}

@Composable
fun TrackingPaneHint() {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(
            stringResource(R.string.split_pane_hint),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
