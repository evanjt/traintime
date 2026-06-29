package com.evanjt.traintime.ui.station

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.PhoneWatchType
import com.evanjt.traintime.ui.theme.tint
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StationScreen(
    viewModel: MainViewModel,
    onOpenSettings: (focusWatch: Boolean) -> Unit,
) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        // Header: mode picker + GPS + settings
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp),
        ) {
            ModePicker(
                availableModes = viewModel.availableModes,
                currentMode = viewModel.currentMode,
                onSelect = { viewModel.selectMode(it) },
            )
            Spacer(Modifier.weight(1f))
            // Watch link indicator — shown when a watch is known. For Garmin, the colour
            // tracks liveness (green = open and synced, amber = connected but app closed,
            // grey = paired but off/away) and a tap launches TrainTime on the watch, showing
            // a spinner until it announces itself.
            if (viewModel.watchLinks.isNotEmpty()) {
                val hasGarmin = viewModel.watchLinks.any { it.type == PhoneWatchType.GARMIN }
                if (hasGarmin) {
                    // The status colour lives on the watch body; while checking, a spinner
                    // runs inside the watch's screen so the whole control reads as "the watch
                    // is working". Footprint is fixed so the header never shifts.
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .clickable { viewModel.openWatchApp() }
                            .padding(end = 12.dp),
                    ) {
                        Icon(
                            Icons.Filled.Watch,
                            contentDescription = "Open TrainTime on the watch",
                            tint = when {
                                viewModel.watchChecking -> secondary
                                viewModel.watchAlive -> Color(0xFF34C759)            // open + synced
                                viewModel.watchKnownButDisconnected -> Color(0xFF8E8E93) // paired, off/away
                                else -> Color(0xFFFFB300)                            // connected, app closed
                            },
                            modifier = Modifier.size(30.dp),
                        )
                        if (viewModel.watchChecking) {
                            CircularProgressIndicator(
                                color = palette.platform,
                                strokeWidth = 1.5.dp,
                                modifier = Modifier.size(15.dp),
                            )
                        }
                    }
                } else {
                    Icon(
                        Icons.Filled.Watch,
                        contentDescription = "Watch — open settings",
                        tint = palette.platform,
                        modifier = Modifier
                            .clickable { onOpenSettings(true) }
                            .padding(end = 12.dp),
                    )
                }
            }
            Icon(
                Icons.Filled.LocationOn,
                contentDescription = "GPS quality",
                tint = viewModel.gpsQuality.tint,
            )
            IconButton(onClick = { onOpenSettings(false) }) {
                Icon(Icons.Filled.Settings, contentDescription = "Settings", tint = secondary)
            }
        }

        // Station name — tappable to open picker
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { viewModel.showStationPicker = true }
                .padding(top = 10.dp),
        ) {
            Text(
                viewModel.stationName,
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (viewModel.stations.size > 1) {
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = "Pick station",
                    tint = secondary,
                    modifier = Modifier.padding(start = 4.dp),
                )
            }
        }

        // Walk info
        Text(
            viewModel.walkInfo,
            color = secondary,
            fontSize = 13.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 8.dp),
        )

        // Departure list
        if (viewModel.departures.isEmpty() && viewModel.favouriteDepartures.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (viewModel.stations.isEmpty()) {
                    Text(
                        viewModel.status,
                        color = secondary,
                        fontSize = 14.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 32.dp),
                    )
                } else {
                    CircularProgressIndicator(color = secondary)
                }
            }
        } else {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp)
                    .padding(bottom = 12.dp),
            ) {
                PullToRefreshBox(
                    isRefreshing = refreshing,
                    onRefresh = {
                        scope.launch {
                            refreshing = true
                            viewModel.forceRefresh()
                            refreshing = false
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn {
                        // Favourite departures at top
                        items(
                            viewModel.favouriteDepartures,
                            key = { "fav-${it.stableId}" },
                        ) { departure ->
                            DepartureListItem(
                                departure = departure,
                                isFavourite = true,
                                mode = viewModel.currentMode,
                                onSelect = { viewModel.selectFavouriteDeparture(departure) },
                                onToggleFavourite = { viewModel.toggleFavouriteDeparture(departure) },
                            )
                        }
                        // Separator line under favourites
                        if (viewModel.favouriteDepartures.isNotEmpty() && viewModel.departures.isNotEmpty()) {
                            item(key = "fav-separator") {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 4.dp)
                                        .height(2.dp)
                                        .background(palette.favouriteSeparator),
                                )
                            }
                        }
                        // Regular departures
                        itemsIndexed(
                            viewModel.departures,
                            key = { _, dep -> "dep-${dep.stableId}" },
                        ) { index, departure ->
                            DepartureListItem(
                                departure = departure,
                                isFavourite = viewModel.isDepartureFavourite(departure),
                                mode = viewModel.currentMode,
                                onSelect = { viewModel.selectDeparture(index) },
                                onToggleFavourite = { viewModel.toggleFavouriteDeparture(departure) },
                            )
                            if (index < viewModel.departures.size - 1) {
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.12f),
                                    modifier = Modifier.padding(horizontal = 16.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// Swipe-from-left to (un)favourite, long-press for the same, tap to select —
// the Android mapping of iOS swipeActions + contextMenu + row tap.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DepartureListItem(
    departure: Departure,
    isFavourite: Boolean,
    mode: com.evanjt.traintime.data.model.TransportMode,
    onSelect: () -> Unit,
    onToggleFavourite: () -> Unit,
) {
    val palette = LocalAppPalette.current
    val dismissState = rememberSwipeToDismissBoxState()

    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue == SwipeToDismissBoxValue.StartToEnd) {
            onToggleFavourite()
            dismissState.reset()
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromEndToStart = false,
        backgroundContent = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxSize()
                    .background(palette.favouriteStar)
                    .padding(horizontal = 20.dp),
            ) {
                Icon(
                    if (isFavourite) Icons.Filled.StarBorder else Icons.Filled.Star,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(22.dp),
                )
                Spacer(Modifier.size(8.dp))
                Text(
                    if (isFavourite) "Unfavourite" else "Favourite",
                    color = Color.White,
                    fontWeight = FontWeight.Medium,
                )
            }
        },
    ) {
        Box(
            Modifier
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .combinedClickable(
                    onClick = { if (!departure.isGone) onSelect() },
                    onLongClick = onToggleFavourite,
                ),
        ) {
            DepartureRow(departure = departure, isFavourite = isFavourite, mode = mode)
        }
    }
}
