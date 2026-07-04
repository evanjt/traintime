package com.evanjt.traintime.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition

// Flat, dense list (like the Apple watch) rather than a ScalingLazyColumn, so
// several departures are visible at once. The Vignette fades the round top/bottom
// edges so flat rows don't look clipped. Insets are percentage-based to scale
// across watch sizes.
@Composable
fun WearStationListScreen(
    vm: WearViewModel,
    onOpenPicker: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val listState = rememberLazyListState()
    val config = LocalConfiguration.current
    val sidePad = (config.screenWidthDp * 0.07f).dp
    val topPad = (config.screenHeightDp * 0.16f).dp
    val bottomPad = (config.screenHeightDp * 0.16f).dp

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(lazyListState = listState) },
    ) {
        LazyColumn(
            state = listState,
            contentPadding = PaddingValues(start = sidePad, end = sidePad, top = topPad, bottom = bottomPad),
            modifier = Modifier.fillMaxSize(),
        ) {
            // Mode selector — centred so it clears the round top bezel.
            item {
                Row(
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 2.dp),
                ) { ModeIconRow(vm) }
            }

            // Station name (tap to switch) + GPS dot + settings gear.
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth().clickable(enabled = vm.stations.size > 1) { onOpenPicker() },
                ) {
                    GpsIcon(vm.gpsQuality, Modifier.padding(end = 4.dp))
                    Text(
                        vm.stationName.uppercase(),
                        color = MaterialTheme.colors.onBackground,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                    if (vm.stations.size > 1) {
                        Icon(
                            Icons.Filled.KeyboardArrowDown,
                            contentDescription = "Switch station",
                            tint = MaterialTheme.colors.onSurfaceVariant,
                            modifier = Modifier.size(13.dp),
                        )
                    }
                }
            }

            if (vm.walkInfo.isNotEmpty()) {
                item {
                    Text(
                        vm.walkInfo,
                        color = MaterialTheme.colors.onSurfaceVariant,
                        fontSize = 9.sp,
                        maxLines = 1,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 2.dp),
                    )
                }
            }

            item { Divider() }

            val favourites = vm.favouriteDepartures
            if (favourites.isNotEmpty()) {
                itemsIndexed(favourites, key = { _, d -> "fav-${d.stableId}" }) { _, dep ->
                    WearDepartureRow(
                        departure = dep,
                        isFavourite = true,
                        mode = vm.currentMode,
                        onClick = { vm.selectDeparture(dep) },
                        onLongClick = { vm.toggleFavouriteDeparture(dep) },
                    )
                }
                item { GoldSeparator() }
            }

            if (vm.departures.isEmpty()) {
                item {
                    Text(
                        vm.status,
                        color = MaterialTheme.colors.onSurfaceVariant,
                        fontSize = 12.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    )
                }
            } else {
                itemsIndexed(vm.departures, key = { _, d -> "dep-${d.stableId}" }) { index, dep ->
                    WearDepartureRow(
                        departure = dep,
                        isFavourite = vm.isDepartureFavourite(dep),
                        mode = vm.currentMode,
                        onClick = { vm.selectDeparture(index) },
                        onLongClick = { vm.toggleFavouriteDeparture(dep) },
                    )
                }
            }

            item {
                Row(
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp).clickable { onOpenSettings() },
                ) {
                    Icon(
                        Icons.Filled.Settings,
                        contentDescription = "Settings",
                        tint = MaterialTheme.colors.onSurfaceVariant,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun Divider() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp, vertical = 3.dp)
            .height(1.dp)
            .background(MaterialTheme.colors.onSurfaceVariant.copy(alpha = 0.3f)),
    )
}
