package com.evanjt.traintime.wear

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.ChipColors
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import com.evanjt.traintime.data.model.TransportMode

@Composable
fun WearStationListScreen(
    vm: WearViewModel,
    onOpenPicker: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
        ) {
            item { StationHeader(vm, onOpenPicker) }

            if (vm.availableModes.size > 1) {
                item { ModeChips(vm) }
            }

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
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    )
                }
            } else {
                itemsIndexed(vm.departures, key = { _, d -> d.stableId }) { index, dep ->
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
                CompactChip(
                    onClick = onOpenSettings,
                    label = { Text("Settings") },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun StationHeader(vm: WearViewModel, onOpenPicker: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
    ) {
        Text(
            vm.stationName,
            color = MaterialTheme.colors.onBackground,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
            modifier = Modifier.padding(top = 2.dp),
        ) {
            GpsDot(vm.gpsQuality)
            if (vm.walkInfo.isNotEmpty()) {
                Spacer(Modifier.width(6.dp))
                Text(vm.walkInfo, color = MaterialTheme.colors.onSurfaceVariant, fontSize = 12.sp, maxLines = 1)
            }
        }
        if (vm.stations.size > 1) {
            CompactChip(
                onClick = onOpenPicker,
                label = { Text("Switch station") },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

@Composable
private fun ModeChips(vm: WearViewModel) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
        modifier = Modifier.fillMaxWidth(),
    ) {
        vm.availableModes.forEach { mode ->
            val selected = mode == vm.currentMode
            val colors: ChipColors =
                if (selected) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors()
            CompactChip(
                onClick = { vm.selectMode(mode) },
                label = { Text(mode.shortLabel, fontSize = 11.sp) },
                colors = colors,
            )
        }
    }
}

private val TransportMode.shortLabel: String
    get() = when (this) {
        TransportMode.TRAIN -> "Train"
        TransportMode.BUS -> "Bus"
        TransportMode.TRAM -> "Tram"
        TransportMode.SPECIAL -> "Spec"
    }
