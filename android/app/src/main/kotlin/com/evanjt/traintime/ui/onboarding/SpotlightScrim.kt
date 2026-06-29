package com.evanjt.traintime.ui.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

// Lightly dims everything except the taught element: a translucent scrim with a
// rounded transparent cut-out punched over the target's bounds. The feature
// shows through fully bright (the tour must never obscure what it's explaining).
// BlendMode.Clear needs an owned offscreen layer to composite, hence graphicsLayer.
@Composable
fun SpotlightScrim(hole: Rect?, modifier: Modifier = Modifier) {
    Canvas(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen),
    ) {
        drawRect(Color.Black.copy(alpha = 0.32f))
        if (hole != null) {
            val pad = 6.dp.toPx()
            val left = (hole.left - pad).coerceAtLeast(0f)
            val top = (hole.top - pad).coerceAtLeast(0f)
            val right = (hole.right + pad).coerceAtMost(size.width)
            val bottom = (hole.bottom + pad).coerceAtMost(size.height)
            drawRoundRect(
                color = Color.Transparent,
                topLeft = Offset(left, top),
                size = Size((right - left).coerceAtLeast(0f), (bottom - top).coerceAtLeast(0f)),
                cornerRadius = CornerRadius(14.dp.toPx()),
                blendMode = BlendMode.Clear,
            )
        }
    }
}
