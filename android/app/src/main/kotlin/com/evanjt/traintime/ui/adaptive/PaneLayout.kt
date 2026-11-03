package com.evanjt.traintime.ui.adaptive

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
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

enum class WidthClass { COMPACT, MEDIUM, EXPANDED }

enum class PaneLayout { BOARD, TRACKING, SPLIT_TRACKING, SPLIT_HINT }

// Material window size class breakpoints, read from the window width in dp.
fun widthClassOf(widthDp: Float): WidthClass = when {
    widthDp < 600f -> WidthClass.COMPACT
    widthDp < 840f -> WidthClass.MEDIUM
    else -> WidthClass.EXPANDED
}

// Only an expanded window has room for the board beside tracking. Compact and
// medium keep the board, then tracking full-screen. State 3 (inactive) shows
// the board with its scrim either way.
fun paneLayout(width: WidthClass, appState: Int): PaneLayout = when {
    width == WidthClass.EXPANDED && appState == 2 -> PaneLayout.SPLIT_TRACKING
    width == WidthClass.EXPANDED -> PaneLayout.SPLIT_HINT
    appState == 2 -> PaneLayout.TRACKING
    else -> PaneLayout.BOARD
}

// A readable board column; tracking takes the rest of the window.
val BOARD_PANE_WIDTH = 400.dp

@Composable
fun TwoPane(
    board: @Composable () -> Unit,
    detail: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxSize()) {
        Box(Modifier.width(BOARD_PANE_WIDTH).fillMaxHeight()) { board() }
        VerticalDivider()
        Box(Modifier.weight(1f).fillMaxHeight()) { detail() }
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
