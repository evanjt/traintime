package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.Thresholds

// Port of TrackingBarView.swift: ±3 minutes of buffer maps to half the
// bar. Dark green = guaranteed, light green = saved by the delay,
// amber = recoverable, dark red = irrecoverable.
@Composable
fun TrackingBar(
    schedBuf: Double,
    effectBuf: Double,
    hasGps: Boolean,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(12.dp)
            .clip(RoundedCornerShape(3.dp)),
    ) {
        val width = size.width
        val midX = width / 2
        val scale = Thresholds.BAR_SCALE

        fun position(buffer: Double): Float {
            val clamped = buffer.coerceIn(-scale, scale)
            return (midX + (clamped / scale) * midX).toFloat()
        }

        drawRect(palette.trackingBarBackground)

        if (!hasGps) {
            drawRect(palette.barGray)
        } else {
            val schedPos = position(schedBuf)
            val effectPos = position(effectBuf)

            if (schedBuf >= 0 && effectBuf >= 0) {
                drawRect(
                    palette.darkGreen,
                    topLeft = Offset(midX, 0f),
                    size = Size((schedPos - midX).coerceAtLeast(0f), size.height),
                )
                if (effectPos > schedPos) {
                    drawRect(
                        palette.lightGreen,
                        topLeft = Offset(schedPos, 0f),
                        size = Size(effectPos - schedPos, size.height),
                    )
                }
            } else if (schedBuf < 0 && effectBuf < 0) {
                drawRect(
                    palette.darkRed,
                    topLeft = Offset(effectPos, 0f),
                    size = Size((midX - effectPos).coerceAtLeast(0f), size.height),
                )
                if (schedPos < effectPos) {
                    drawRect(
                        palette.amber,
                        topLeft = Offset(schedPos, 0f),
                        size = Size(effectPos - schedPos, size.height),
                    )
                }
            } else if (schedBuf < 0 && effectBuf >= 0) {
                drawRect(
                    palette.amber,
                    topLeft = Offset(schedPos, 0f),
                    size = Size((midX - schedPos).coerceAtLeast(0f), size.height),
                )
                drawRect(
                    palette.lightGreen,
                    topLeft = Offset(midX, 0f),
                    size = Size((effectPos - midX).coerceAtLeast(0f), size.height),
                )
            }
        }

        // Centre marker
        drawRect(
            palette.barGray.copy(alpha = 0.8f),
            topLeft = Offset(midX - 1, 0f),
            size = Size(2f, size.height),
        )
    }
}
