package ch.traintime.phone.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SatelliteAlt
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import ch.traintime.shared.models.GPSQuality

@Composable
fun GpsIndicator(quality: GPSQuality) {
    Icon(
        imageVector = Icons.Filled.SatelliteAlt,
        contentDescription = "GPS",
        tint = Color(quality.colorInt),
        modifier = Modifier.size(16.dp)
    )
}
