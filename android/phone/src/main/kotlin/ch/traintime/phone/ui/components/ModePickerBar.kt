package ch.traintime.phone.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ch.traintime.shared.models.TransportMode

private val MODE_ICONS = mapOf(
    TransportMode.TRAIN to "\uD83D\uDE86",
    TransportMode.BUS to "\uD83D\uDE8C",
    TransportMode.TRAM to "\uD83D\uDE8A",
    TransportMode.SPECIAL to "\uD83D\uDEA1"
)

@Composable
fun ModePickerBar(
    availableModes: List<TransportMode>,
    currentMode: TransportMode,
    onSelect: (TransportMode) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        TransportMode.entries.forEach { mode ->
            val isAvailable = mode in availableModes
            val isCurrent = mode == currentMode

            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(
                        when {
                            isCurrent && isAvailable -> Color.White.copy(alpha = 0.15f)
                            else -> Color.Transparent
                        }
                    )
                    .clickable(enabled = isAvailable) { onSelect(mode) },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = MODE_ICONS[mode] ?: "",
                    fontSize = 18.sp,
                    color = when {
                        !isAvailable -> Color.White.copy(alpha = 0.15f)
                        isCurrent -> Color.White
                        else -> Color.Gray
                    }
                )
            }
        }
    }
}
