package com.evanjt.traintime.ui.adaptive

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker

// The one read of the window's folds and hinges. A book-style foldable reports
// its hinge here while flat as well as half-open, and only folds that cross
// this window are listed.
@Composable
fun rememberFoldingFeatures(): List<FoldingFeature> {
    val activity = LocalActivity.current ?: return emptyList()
    val layoutInfo = remember(activity) {
        WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity)
    }
    val info by layoutInfo.collectAsState(initial = null)
    return info?.displayFeatures?.filterIsInstance<FoldingFeature>().orEmpty()
}

// The vertical fold the split should follow, in dp from the pane's left edge.
// Only a fold that separates the window (half-open, or two screens) or hides
// pixels counts. A flat crease draws fine, and a tabletop fold runs along the
// split rather than across it. Fold bounds are in window pixels.
fun verticalFoldOf(features: List<FoldingFeature>, paneLeftPx: Float, density: Float): VerticalFold? {
    val fold = features.firstOrNull {
        it.orientation == FoldingFeature.Orientation.VERTICAL &&
            (it.isSeparating || it.occlusionType == FoldingFeature.OcclusionType.FULL)
    } ?: return null
    return VerticalFold(
        startDp = (fold.bounds.left - paneLeftPx) / density,
        endDp = (fold.bounds.right - paneLeftPx) / density,
    )
}
