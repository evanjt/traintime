package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.R

@Composable
fun DirectionArrow(degrees: Double?) {
    if (degrees != null) {
        Icon(
            Icons.Filled.Navigation,
            contentDescription = stringResource(R.string.direction_to_station_cd),
            tint = Color.White,
            modifier = Modifier
                .size(18.dp)
                .rotate(degrees.toFloat()),
        )
    }
}
