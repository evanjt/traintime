package com.evanjt.traintime.ui.station

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.linePill
import kotlin.math.floor

// The live session pinned at the top of the board when tracking continues in
// the background. A distinct card (not a favourite): a green LIVE dot, the line
// pill, destination, minutes, tap to re-open full tracking, ■ to stop.
@Composable
fun NowTrackingCard(
    focused: FocusedDeparture,
    mode: TransportMode,
    nowEpochSeconds: Long,
    onResume: () -> Unit,
    onStop: () -> Unit,
) {
    val palette = LocalAppPalette.current
    val minutes = floor(focused.minutesUntil(nowEpochSeconds)).toInt().coerceAtLeast(0)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(palette.ahead.copy(alpha = 0.14f))
            .clickable(onClick = onResume)
            .padding(start = 12.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(
            Modifier.size(9.dp).clip(CircleShape).background(palette.ahead),
        )
        Text(
            text = stringResource(R.string.tracking_now).uppercase(),
            color = palette.ahead,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            modifier = Modifier.padding(start = 8.dp, end = 10.dp),
        )
        Text(
            text = focused.lineNumber,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 13.sp,
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(palette.linePill(focused.lineNumber, mode))
                .padding(horizontal = 7.dp, vertical = 2.dp),
        )
        Text(
            text = focused.destination,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            modifier = Modifier.padding(start = 8.dp).weight(1f),
        )
        Text(
            text = stringResource(R.string.n_min_fmt, minutes),
            color = MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 6.dp),
        )
        IconButton(onClick = onStop) {
            Icon(
                Icons.Filled.Close,
                contentDescription = stringResource(R.string.stop_tracking),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
