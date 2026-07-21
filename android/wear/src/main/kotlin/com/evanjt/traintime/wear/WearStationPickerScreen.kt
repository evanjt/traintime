package com.evanjt.traintime.wear

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.wear.R

@Composable
fun WearStationPickerScreen(vm: WearViewModel, onClose: () -> Unit) {
    val listState = rememberScalingLazyListState()
    val config = LocalConfiguration.current
    val sidePad = (config.screenWidthDp * 0.06f).dp
    val vertPad = (config.screenHeightDp * 0.14f).dp
    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            state = listState,
            contentPadding = PaddingValues(start = sidePad, end = sidePad, top = vertPad, bottom = vertPad),
            modifier = Modifier.fillMaxSize(),
        ) {
            item {
                Text(
                    stringResource(R.string.nearby_stations),
                    color = MaterialTheme.colors.onBackground,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                )
            }
            itemsIndexed(vm.stations, key = { _, s -> s.id }) { index, station ->
                StationPickerRow(
                    station = station,
                    pinned = vm.isStationPinned(station.id),
                    current = station.id == vm.currentStation?.id,
                    onClick = { vm.selectStation(index); onClose() },
                    onLongClick = { vm.togglePinnedStation(station) },
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun StationPickerRow(
    station: Station,
    pinned: Boolean,
    current: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val palette = LocalWearPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colors.surface)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        if (pinned) {
            Text("★", color = palette.favouriteStar, fontSize = 13.sp)
            Spacer(Modifier.width(6.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                station.name ?: stringResource(CoreR.string.station_fallback),
                color = MaterialTheme.colors.onSurface,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            station.dist?.let {
                Text(GeoUtils.formatWalkInfo(LocalContext.current, it), color = MaterialTheme.colors.onSurfaceVariant, fontSize = 11.sp, maxLines = 1)
            }
        }
        // Checkmark for the station currently shown, like the Apple watch picker.
        if (current) {
            Spacer(Modifier.width(6.dp))
            Text("✓", color = MaterialTheme.colors.primary, fontSize = 13.sp)
        }
    }
}
