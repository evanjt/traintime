package ch.traintime.phone.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import ch.traintime.shared.AppColors
import ch.traintime.shared.Thresholds

@Composable
fun TrackingBar(
    schedBuf: Double,
    effectBuf: Double,
    hasGPS: Boolean,
    modifier: Modifier = Modifier
) {
    val scale = Thresholds.BAR_SCALE

    Canvas(modifier = modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height
        val midX = width / 2

        // Background
        drawRect(Color.Black, size = size)

        if (!hasGPS) {
            drawRect(Color(AppColors.BAR_GRAY), size = size)
        } else {
            fun bufToPos(buf: Double): Float {
                val clamped = buf.coerceIn(-scale, scale)
                val fraction = clamped / scale
                return midX + (fraction * midX).toFloat()
            }

            val schedPos = bufToPos(schedBuf)
            val effectPos = bufToPos(effectBuf)

            if (schedBuf >= 0 && effectBuf >= 0) {
                // Both positive: dark green + light green
                drawRect(
                    Color(AppColors.DARK_GREEN),
                    topLeft = Offset(midX, 0f),
                    size = Size(maxOf(0f, schedPos - midX), height)
                )
                if (effectPos > schedPos) {
                    drawRect(
                        Color(AppColors.LIGHT_GREEN),
                        topLeft = Offset(schedPos, 0f),
                        size = Size(effectPos - schedPos, height)
                    )
                }
            } else if (schedBuf < 0 && effectBuf < 0) {
                // Both negative: dark red + amber
                drawRect(
                    Color(AppColors.DARK_RED),
                    topLeft = Offset(effectPos, 0f),
                    size = Size(maxOf(0f, midX - effectPos), height)
                )
                if (schedPos < effectPos) {
                    drawRect(
                        Color(AppColors.AMBER),
                        topLeft = Offset(schedPos, 0f),
                        size = Size(effectPos - schedPos, height)
                    )
                }
            } else if (schedBuf < 0 && effectBuf >= 0) {
                // Mixed: amber from schedBuf to mid, light green from mid to effectBuf
                drawRect(
                    Color(AppColors.AMBER),
                    topLeft = Offset(schedPos, 0f),
                    size = Size(maxOf(0f, midX - schedPos), height)
                )
                drawRect(
                    Color(AppColors.LIGHT_GREEN),
                    topLeft = Offset(midX, 0f),
                    size = Size(maxOf(0f, effectPos - midX), height)
                )
            }
        }

        // Center marker
        drawRect(
            Color(AppColors.BAR_GRAY).copy(alpha = 0.8f),
            topLeft = Offset(midX - 1, 0f),
            size = Size(2f, height)
        )
    }
}
