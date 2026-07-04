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
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

// Lightly dims everything except the taught element: a translucent scrim with a rounded
// transparent cut-out punched over the target's bounds, ringed with a dashed accent border so
// the spotlighted feature reads clearly against the dim (especially in dark mode).
// BlendMode.Clear needs an owned offscreen layer to composite, hence graphicsLayer.
@Composable
fun SpotlightScrim(hole: Rect?, accent: Color, modifier: Modifier = Modifier) {
    Canvas(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen),
    ) {
        drawRect(Color.Black.copy(alpha = 0.32f))
        if (hole == null) return@Canvas

        val pad = 6.dp.toPx()
        val left = (hole.left - pad).coerceAtLeast(0f)
        val top = (hole.top - pad).coerceAtLeast(0f)
        val right = (hole.right + pad).coerceAtMost(size.width)
        val bottom = (hole.bottom + pad).coerceAtMost(size.height)
        val tl = Offset(left, top)
        val sz = Size((right - left).coerceAtLeast(0f), (bottom - top).coerceAtLeast(0f))
        val radius = CornerRadius(14.dp.toPx())

        drawRoundRect(
            color = Color.Transparent,
            topLeft = tl,
            size = sz,
            cornerRadius = radius,
            blendMode = BlendMode.Clear,
        )
        drawRoundRect(
            color = accent,
            topLeft = tl,
            size = sz,
            cornerRadius = radius,
            style = Stroke(
                width = 2.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(22f, 14f)),
            ),
        )
    }
}
