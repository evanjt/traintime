package com.evanjt.traintime.ui.station

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsBoat
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.Train
import androidx.compose.material.icons.filled.Tram
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.data.model.TransportMode

val TransportMode.icon: ImageVector
    get() = when (this) {
        TransportMode.TRAIN -> Icons.Filled.Train
        TransportMode.BUS -> Icons.Filled.DirectionsBus
        TransportMode.TRAM -> Icons.Filled.Tram
        TransportMode.SPECIAL -> Icons.Filled.DirectionsBoat
    }

@Composable
fun ModePicker(
    availableModes: List<TransportMode>,
    currentMode: TransportMode,
    onSelect: (TransportMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    val accent = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(modifier = modifier) {
        TransportMode.entries.forEach { mode ->
            val isAvailable = mode in availableModes
            val isSelected = mode == currentMode && isAvailable
            val tint = when {
                isSelected -> accent
                isAvailable -> secondary
                else -> secondary.copy(alpha = 0.3f)
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
                modifier = Modifier
                    .width(64.dp)
                    .height(52.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isSelected) accent.copy(alpha = 0.15f) else Color.Transparent)
                    .clickable(enabled = isAvailable) { onSelect(mode) },
            ) {
                val label = stringResource(mode.labelRes)
                Icon(mode.icon, contentDescription = label, tint = tint)
                Text(label, fontSize = 10.sp, color = tint)
            }
        }
    }
}
