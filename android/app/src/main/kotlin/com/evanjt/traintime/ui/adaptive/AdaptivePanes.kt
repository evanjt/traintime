package com.evanjt.traintime.ui.adaptive

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.AnchoredDraggableDefaults
import androidx.compose.foundation.gestures.AnchoredDraggableState
import androidx.compose.foundation.gestures.DraggableAnchors
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.anchoredDraggable
import androidx.compose.foundation.gestures.animateTo
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.R
import kotlin.math.roundToInt

const val CARD_GRABBER_TAG = "card_grabber"
private val GRABBER_WIDTH = 20.dp

// The one place the layout decision becomes panes, so the app and its
// snapshots draw the same thing at the same size. tracking gets true when the
// pane carries the x, so the screen leaves out its own Stop.
@Composable
fun AdaptivePanes(
    widthDp: Float,
    heightDp: Float,
    fold: VerticalFold?,
    appState: Int,
    stop: CardStop,
    onStopChange: (CardStop) -> Unit,
    onStopTracking: () -> Unit,
    board: @Composable () -> Unit,
    tracking: @Composable (carriesStop: Boolean) -> Unit,
    peek: @Composable () -> Unit,
    hint: @Composable () -> Unit,
) {
    val layout = paneLayout(widthDp, heightDp, fold, appState, stop)
    val tracked = appState == 2
    when (layout.mode) {
        PaneMode.BOARD -> board()
        PaneMode.TRACKING -> tracking(false)
        PaneMode.SIDE_BY_SIDE -> Row(Modifier.fillMaxSize()) {
            Box(Modifier.width(layout.boardDp.dp).fillMaxHeight()) { board() }
            // The fold itself separates the panes, and nothing is drawn under
            // an occluded strip, so only a window without a fold gets a divider.
            if (layout.onFold) {
                Spacer(Modifier.width((layout.detailStartDp - layout.boardDp).dp))
            } else {
                VerticalDivider()
            }
            Box(Modifier.weight(1f).fillMaxHeight()) {
                if (tracked) {
                    tracking(true)
                    StopTrackingButton(onStopTracking, Modifier.align(Alignment.TopEnd))
                } else {
                    hint()
                }
            }
        }
        PaneMode.CARD -> if (tracked) {
            TrackingCard(widthDp, fold, layout.stop ?: CardStop.HALF, onStopChange, onStopTracking, board, tracking, peek)
        } else {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.width(layout.boardDp.dp).fillMaxHeight()) { board() }
                Box(Modifier.weight(1f).fillMaxHeight()) { hint() }
            }
        }
    }
}

// The board is the base layer and lays out in the width the card leaves it.
// The card is dragged by its leading-edge grabber between the stops' edges.
@Composable
private fun TrackingCard(
    widthDp: Float,
    fold: VerticalFold?,
    at: CardStop,
    onStopChange: (CardStop) -> Unit,
    onStopTracking: () -> Unit,
    board: @Composable () -> Unit,
    tracking: @Composable (carriesStop: Boolean) -> Unit,
    peek: @Composable () -> Unit,
) {
    val density = LocalDensity.current.density
    val edges = cardEdges(widthDp, fold)
    val anchors = DraggableAnchors { edges.forEach { (stop, dp) -> stop at dp * density } }
    val state = remember { AnchoredDraggableState(initialValue = at, anchors = anchors) }
    val currentAt by rememberUpdatedState(at)
    val report by rememberUpdatedState(onStopChange)
    LaunchedEffect(anchors) { state.updateAnchors(anchors, currentAt) }
    LaunchedEffect(at) { if (state.settledValue != at) state.animateTo(at) }
    LaunchedEffect(state.settledValue) { if (state.settledValue != currentAt) report(state.settledValue) }

    val edgePx = state.offset.takeUnless { it.isNaN() } ?: ((edges[at] ?: 0f) * density)
    val edgeDp = edgePx / density
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.width(edgeDp.dp).fillMaxHeight()) { board() }
        Surface(
            modifier = Modifier
                .offset { IntOffset(edgePx.roundToInt(), 0) }
                .width((widthDp - edgeDp).coerceAtLeast(0f).dp)
                .fillMaxHeight(),
            // At Full the card is the window, so it has no edge to round.
            shape = if (edgePx < 1f) RectangleShape else RoundedCornerShape(topStart = 16.dp, bottomStart = 16.dp),
            shadowElevation = 8.dp,
            tonalElevation = 1.dp,
        ) {
            Row {
                val expandLabel = stringResource(R.string.card_expand)
                val collapseLabel = stringResource(R.string.card_collapse)
                val handleLabel = stringResource(R.string.card_handle_cd)
                Box(
                    Modifier
                        .width(GRABBER_WIDTH)
                        .fillMaxHeight()
                        .testTag(CARD_GRABBER_TAG)
                        .anchoredDraggable(
                            state = state,
                            reverseDirection = false,
                            orientation = Orientation.Horizontal,
                            flingBehavior = AnchoredDraggableDefaults.flingBehavior(state),
                        )
                        .semantics {
                            contentDescription = handleLabel
                            cardStopOpened(at)?.let { next -> expand(expandLabel) { onStopChange(next); true } }
                            cardStopClosed(at)?.let { next -> collapse(collapseLabel) { onStopChange(next); true } }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .size(width = 4.dp, height = 40.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)),
                    )
                }
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    if (state.currentValue == CardStop.PEEK) peek() else tracking(true)
                    StopTrackingButton(onStopTracking, Modifier.align(Alignment.TopEnd))
                }
            }
        }
    }
}

@Composable
private fun StopTrackingButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    IconButton(onClick = onClick, modifier = modifier.padding(4.dp)) {
        Icon(
            Icons.Filled.Close,
            contentDescription = stringResource(R.string.stop_tracking),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// With nothing tracked the hint is a small card, never a full empty pane.
@Composable
fun TrackingPaneHint() {
    Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            tonalElevation = 2.dp,
            shadowElevation = 2.dp,
        ) {
            Text(
                stringResource(R.string.split_pane_hint),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
            )
        }
    }
}
