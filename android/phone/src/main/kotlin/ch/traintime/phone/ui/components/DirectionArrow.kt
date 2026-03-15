package ch.traintime.phone.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.unit.dp

@Composable
fun DirectionArrow(degrees: Double?, modifier: Modifier = Modifier) {
    if (degrees == null) return

    Canvas(modifier = modifier.size(20.dp)) {
        rotate(degrees.toFloat()) {
            val path = Path().apply {
                moveTo(size.width / 2, 0f)
                lineTo(size.width, size.height)
                lineTo(size.width / 2, size.height * 0.7f)
                lineTo(0f, size.height)
                close()
            }
            drawPath(path, Color.White)
        }
    }
}
