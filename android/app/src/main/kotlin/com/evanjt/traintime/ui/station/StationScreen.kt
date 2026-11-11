package com.evanjt.traintime.ui.station

import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocationOff
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.domain.ConnectIqStore
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.PhoneWatchType
import com.evanjt.traintime.ui.adaptive.BoardPicker
import com.evanjt.traintime.ui.adaptive.boardPickersLocked
import com.evanjt.traintime.ui.adaptive.trackedRowIndex
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
    val context = LocalContext.current
    val garminStoreUrl = ConnectIqStore.url(LocalConfiguration.current.locales[0].language)
    val pickersLocked = boardPickersLocked(viewModel.appState)

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
                onSelect = { viewModel.tapPicker(BoardPicker.Mode(it)) },
                dimmed = pickersLocked,
            )
            Spacer(Modifier.weight(1f))
            // Watch link indicator, shown when a watch is known. For Garmin, the colour
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
                            contentDescription = stringResource(R.string.open_watch_cd),
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
                        contentDescription = stringResource(R.string.watch_settings_cd),
                        tint = palette.platform,
                        modifier = Modifier
                            .clickable { onOpenSettings(true) }
                            .padding(end = 12.dp),
                    )
                }
            }
            // A crossed pin means zero proof of position: no fix at all, or only
            // a cached coordinate that may be from another city.
            Icon(
                when (viewModel.gpsQuality) {
                    GpsQuality.LAST_KNOWN, GpsQuality.UNAVAILABLE -> Icons.Filled.LocationOff
                    else -> Icons.Filled.LocationOn
                },
                contentDescription = stringResource(R.string.gps_quality_cd),
                tint = viewModel.gpsQuality.tint,
            )
            IconButton(onClick = { onOpenSettings(false) }) {
                Icon(Icons.Filled.Settings, contentDescription = stringResource(CoreR.string.settings), tint = secondary)
            }
        }

        if (viewModel.garminTip) {
            GarminTipCard(
                onOpen = {
                    viewModel.dismissGarminTip()
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(garminStoreUrl))) }
                },
                onDismiss = { viewModel.dismissGarminTip() },
            )
        }

        // Station name, tappable to open picker
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { viewModel.tapPicker(BoardPicker.Station) }
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
            if (viewModel.stations.size > 1 && !pickersLocked) {
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = stringResource(R.string.pick_station_cd),
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

        // The watch is tracking a departure while the phone shows the board:
        // say so, and (when the full payload is known) tap to follow along.
        viewModel.watchTrackingLabel?.let { label ->
            Row(
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            ) {
                Surface(
                    onClick = { viewModel.followWatchTracking() },
                    enabled = viewModel.watchTrackingFollowable,
                    shape = RoundedCornerShape(12.dp),
                    tonalElevation = 3.dp,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    ) {
                        Icon(
                            Icons.Filled.Watch,
                            contentDescription = null,
                            tint = Color(0xFF34C759),
                            modifier = Modifier.size(16.dp),
                        )
                        Text(stringResource(R.string.tracking_on_watch_fmt, label), fontSize = 13.sp)
                    }
                }
            }
        }

        // Departure list
        if (viewModel.departures.isEmpty() && viewModel.favouriteDepartures.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (viewModel.stations.isEmpty()) {
                    if (viewModel.isOutOfBounds) {
                        SwissOutlineBackdrop(color = secondary.copy(alpha = 0.3f))
                    }
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
                    // A timer or switch refresh dims the list and shows a slim
                    // bar, so the board freezes in place rather than vanishing.
                    // The pull gesture has its own indicator, so skip it then.
                    if (viewModel.departuresRefreshing && !refreshing) {
                        LinearProgressIndicator(
                            color = palette.platform,
                            trackColor = Color.Transparent,
                            modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter),
                        )
                    }
                    LazyColumn(
                        modifier = Modifier.alpha(if (viewModel.departuresRefreshing) 0.5f else 1f),
                    ) {
                        // Live session continuing in the background, pinned above
                        // everything: tap to re-open full tracking, X to stop.
                        val nowTracking = viewModel.backgroundTracked
                        if (nowTracking != null) {
                            item(key = "now-tracking") {
                                NowTrackingCard(
                                    focused = nowTracking,
                                    mode = viewModel.currentMode,
                                    nowEpochSeconds = System.currentTimeMillis() / 1000,
                                    onResume = { viewModel.resumeBackgroundTracking() },
                                    onStop = { viewModel.stopSession() },
                                )
                            }
                        }
                        // Favourite departures at top
                        val trackedFavourite = trackedRowIndex(viewModel.favouriteDepartures, viewModel.appState, viewModel.focusedTrain)
                        val trackedDeparture = trackedRowIndex(viewModel.departures, viewModel.appState, viewModel.focusedTrain)
                        itemsIndexed(
                            viewModel.favouriteDepartures,
                            key = { _, dep -> "fav-${dep.stableId}" },
                        ) { index, departure ->
                            DepartureListItem(
                                departure = departure,
                                isFavourite = true,
                                selected = index == trackedFavourite,
                                mode = viewModel.currentMode,
                                onSelect = { viewModel.selectFavouriteDeparture(departure) },
                                onToggleFavourite = { viewModel.toggleFavouriteDeparture(departure) },
                                onSaveAsReminder = { viewModel.saveDepartureAsPending(departure) },
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
                                selected = index == trackedDeparture,
                                mode = viewModel.currentMode,
                                onSelect = { viewModel.selectDeparture(index) },
                                onToggleFavourite = { viewModel.toggleFavouriteDeparture(departure) },
                                onSaveAsReminder = { viewModel.saveDepartureAsPending(departure) },
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

// A small card under the mode picker pointing at the Garmin watch app. Tap
// opens the Connect IQ Store, the cross hides it for good.
@Composable
private fun GarminTipCard(onOpen: () -> Unit, onDismiss: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 10.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .clickable(onClick = onOpen)
            .padding(start = 12.dp, top = 10.dp, bottom = 10.dp),
    ) {
        Icon(
            Icons.Filled.Watch,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                stringResource(R.string.garmin_tip_text),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 14.sp,
            )
            Text(
                stringResource(R.string.garmin_tip_action),
                color = MaterialTheme.colorScheme.primary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        IconButton(onClick = onDismiss) {
            Icon(
                Icons.Filled.Close,
                contentDescription = stringResource(R.string.garmin_tip_dismiss),
                tint = secondary,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

// Swipe-from-left to (un)favourite, swipe-from-right to save a reminder,
// long-press to (un)favourite, tap to select. The Android mapping of iOS
// swipeActions + contextMenu + row tap.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DepartureListItem(
    departure: Departure,
    isFavourite: Boolean,
    mode: com.evanjt.traintime.data.model.TransportMode,
    onSelect: () -> Unit,
    onToggleFavourite: () -> Unit,
    onSaveAsReminder: () -> Unit,
    selected: Boolean = false,
) {
    val palette = LocalAppPalette.current
    val dismissState = rememberSwipeToDismissBoxState()

    LaunchedEffect(dismissState.currentValue) {
        when (dismissState.currentValue) {
            SwipeToDismissBoxValue.StartToEnd -> {
                onToggleFavourite()
                dismissState.reset()
            }
            SwipeToDismissBoxValue.EndToStart -> {
                onSaveAsReminder()
                dismissState.reset()
            }
            else -> {}
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        // Can't remind about a train that has already left or will not run.
        enableDismissFromEndToStart = departure.isSelectable,
        backgroundContent = {
            if (dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.End,
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.primary)
                        .padding(horizontal = 20.dp),
                ) {
                    Text(
                        stringResource(R.string.remind_me),
                        color = MaterialTheme.colorScheme.onPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Spacer(Modifier.size(8.dp))
                    Icon(
                        Icons.Filled.Notifications,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.size(22.dp),
                    )
                }
            } else {
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
                        if (isFavourite) stringResource(R.string.unfavourite) else stringResource(R.string.favourite),
                        color = Color.White,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }
        },
    ) {
        Box(
            Modifier
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .combinedClickable(
                    onClick = { if (departure.isSelectable) onSelect() },
                    onLongClick = onToggleFavourite,
                ),
        ) {
            DepartureRow(departure = departure, isFavourite = isFavourite, mode = mode, selected = selected)
        }
    }
}
