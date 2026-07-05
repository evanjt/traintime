package com.evanjt.traintime.wear

import android.app.Activity
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.ToggleChip
import androidx.wear.compose.material.ToggleChipDefaults
import com.evanjt.traintime.data.model.Favourite
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.review.ReviewLauncher

@Composable
fun WearSettingsScreen(vm: WearViewModel, onNavigateHome: () -> Unit = {}) {
    val listState = rememberScalingLazyListState()
    val activity = LocalContext.current as? Activity
    val config = LocalConfiguration.current
    val sidePad = (config.screenWidthDp * 0.06f).dp
    val vertPad = (config.screenHeightDp * 0.14f).dp

    LaunchedEffect(Unit) { vm.refreshPhoneLink() }

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            state = listState,
            contentPadding = PaddingValues(start = sidePad, end = sidePad, top = vertPad, bottom = vertPad),
            modifier = Modifier.fillMaxSize(),
        ) {
            // Phone link status, the peer of Garmin's "Phone: Connected" row.
            item {
                Row(
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                ) {
                    Text("Phone  ", color = MaterialTheme.colors.onBackground, fontSize = 13.sp)
                    Text(
                        when (vm.phoneConnected) {
                            true -> "Connected"
                            false -> "Not connected"
                            null -> "…"
                        },
                        color = if (vm.phoneConnected == true) {
                            LocalWearPalette.current.ahead
                        } else {
                            MaterialTheme.colors.onSurfaceVariant
                        },
                        fontSize = 13.sp,
                    )
                }
            }
            item {
                Text(
                    "Default mode",
                    color = MaterialTheme.colors.onBackground,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 2.dp),
                )
            }
            items(TransportMode.entries.toList()) { mode ->
                ToggleChip(
                    checked = vm.defaultMode == mode,
                    onCheckedChange = { vm.updateDefaultMode(mode) },
                    label = { Text(mode.label) },
                    toggleControl = {
                        androidx.wear.compose.material.RadioButton(selected = vm.defaultMode == mode)
                    },
                    colors = ToggleChipDefaults.toggleChipColors(),
                )
            }
            // Quick launch, the peer of Garmin's settings entry: jump to a pinned
            // station, or straight into tracking a favourite line once its
            // departure loads.
            if (vm.pinnedStations.isNotEmpty() || vm.favouritesList.isNotEmpty()) {
                item {
                    Text(
                        "Quick launch",
                        color = MaterialTheme.colors.onBackground,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp),
                    )
                }
                items(vm.pinnedStations) { pinned ->
                    Chip(
                        onClick = {
                            vm.launchStation(pinned.id, pinned.name, pinned.lat, pinned.lon)
                            onNavigateHome()
                        },
                        label = { Text(pinned.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text("Station") },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                items(vm.favouritesList) { fav ->
                    Chip(
                        onClick = {
                            vm.launchFavourite(fav)
                            onNavigateHome()
                        },
                        label = {
                            Text("${fav.lineNumber} ${fav.destination}", maxLines = 1, overflow = TextOverflow.Ellipsis)
                        },
                        secondaryLabel = { Text(fav.stationName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            // Favourites management, like the Apple watch settings (it uses
            // swipe-delete; here a row holds to remove, matching the picker's
            // long-press idiom).
            if (vm.favouritesList.isNotEmpty()) {
                item {
                    Text(
                        "Favourites (${vm.favouritesList.size})",
                        color = MaterialTheme.colors.onBackground,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp),
                    )
                }
                items(vm.favouritesList) { fav ->
                    FavouriteRow(fav, onRemove = { vm.removeFavourite(fav) })
                }
                item {
                    Text(
                        "Hold a favourite to remove it.",
                        color = MaterialTheme.colors.onSurfaceVariant,
                        fontSize = 10.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                    )
                }
            }
            item {
                Chip(
                    onClick = { activity?.let { ReviewLauncher.openStoreListing(it) } },
                    label = { Text("Rate TrainTime") },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            item {
                Text(
                    "TrainTime ${BuildConfig.VERSION_NAME}",
                    color = MaterialTheme.colors.onSurfaceVariant,
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            item {
                Text(
                    "Data: opentransportdata.swiss",
                    color = MaterialTheme.colors.onSurfaceVariant,
                    fontSize = 10.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FavouriteRow(fav: Favourite, onRemove: () -> Unit) {
    val palette = LocalWearPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colors.surface)
            .combinedClickable(onClick = {}, onLongClick = onRemove)
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        Text("★", color = palette.favouriteStar, fontSize = 12.sp)
        Spacer(Modifier.width(6.dp))
        Column(Modifier.weight(1f)) {
            Text(
                "${fav.lineNumber} → ${fav.destination}",
                color = MaterialTheme.colors.onSurface,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                fav.stationName,
                color = MaterialTheme.colors.onSurfaceVariant,
                fontSize = 10.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
