package com.evanjt.traintime.ui.tracking

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.AppPalette
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.linePill
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.OnwardConnection
import com.evanjt.traintime.ui.PhoneWatchType
import com.evanjt.traintime.ui.TrackingStatus
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay

private val departureTimeFormat = DateTimeFormatter.ofPattern("HH:mm")

private fun formatDepartureTime(timestamp: Long): String =
    departureTimeFormat.format(Instant.ofEpochSecond(timestamp).atZone(ZoneId.systemDefault()))

@Composable
fun TrackingScreen(viewModel: MainViewModel) {
    val focused = viewModel.focusedTrain
    val context = LocalContext.current
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant

    // Keep the screen awake while tracking (extended runtime session analogue).
    val view = LocalView.current
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    BackHandler { viewModel.exitToStationView() }

    // Keep the watch link/status fresh for the "Open on watch" button, and the
    // connected-watch list for "Send to Watch".
    LaunchedEffect(Unit) {
        viewModel.refreshWatchLinks()
        viewModel.refreshConnectedWatches()
    }

    // Local 1 s clock so the countdown ticks even when no state changes.
    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) {
        while (true) {
            nowSeconds = System.currentTimeMillis() / 1000
            delay(250)
        }
    }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 24.dp),
        ) {
            // Station name
            Text(
                viewModel.stationName,
                color = secondary,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 8.dp),
            )

            val platChanged = focused?.platformChanged == true

            // Line + destination + star
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(top = 12.dp),
            ) {
                if (focused != null && focused.lineNumber.isNotEmpty()) {
                    Text(
                        focused.lineNumber,
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(7.dp))
                            .background(palette.linePill(focused.lineNumber, viewModel.currentMode))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
                Text(
                    focused?.destination ?: "?",
                    color = if (platChanged) palette.platformChangedOrange else MaterialTheme.colorScheme.onBackground,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
                IconButton(onClick = { viewModel.toggleFavourite() }) {
                    Icon(
                        if (viewModel.isFocusedTrainFavourite) Icons.Filled.Star else Icons.Outlined.StarOutline,
                        contentDescription = stringResource(R.string.toggle_favourite_cd),
                        tint = if (viewModel.isFocusedTrainFavourite) palette.favouriteStar else secondary,
                    )
                }
            }

            // On a saved route the header keeps the train's own terminus; this
            // line carries where the journey actually ends when they differ.
            focused?.routeDestination?.takeIf { it != focused.destination }?.let { routeDest ->
                Text(
                    stringResource(R.string.tracking_route_to_fmt, routeDest),
                    color = secondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }

            // Platform + scheduled time
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(top = 4.dp),
            ) {
                if (focused != null && focused.platform.isNotEmpty()) {
                    Text(
                        stringResource(R.string.platform_full_fmt, focused.platform),
                        color = if (platChanged) palette.platformChangedOrange else secondary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                    )
                }
                if (focused != null) {
                    Text("·", color = secondary)
                    Text(
                        formatDepartureTime(focused.departureTimestamp),
                        color = secondary,
                        fontSize = 12.sp,
                    )
                }
            }

            // Countdown + delay
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(vertical = 8.dp),
            ) {
                Text(
                    focused?.countdownText(nowSeconds) ?: "–",
                    color = countdownColor(focused, nowSeconds, palette, secondary, MaterialTheme.colorScheme.onBackground),
                    fontSize = 56.sp,
                    fontWeight = FontWeight.Bold,
                )
                if (focused != null && focused.delay > 0 && focused.minutesUntil(nowSeconds) >= -0.5) {
                    Text(
                        "+${focused.delay}",
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .background(palette.delay, CircleShape)
                            .padding(horizontal = 10.dp, vertical = 4.dp),
                    )
                }
            }

            // Tracking bar
            TrackingBar(
                schedBuf = viewModel.trackingScheduledBuffer,
                effectBuf = viewModel.trackingEffectiveBuffer,
                hasGps = viewModel.gpsQuality != GpsQuality.UNAVAILABLE &&
                    viewModel.gpsQuality != GpsQuality.LAST_KNOWN,
                modifier = Modifier.padding(horizontal = 24.dp),
            )

            // Status
            val statusColor = when (viewModel.trackingStatus) {
                TrackingStatus.NO_GPS -> palette.barGray
                TrackingStatus.AHEAD -> palette.ahead
                TrackingStatus.ON_TIME -> palette.onTime
                TrackingStatus.BEHIND -> palette.behind
            }
            Text(
                viewModel.trackingStatusText,
                color = statusColor,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 12.dp),
            )

            // Walk info + direction
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(top = 8.dp),
            ) {
                DirectionArrow(viewModel.directionToStation)
                Text(
                    GeoUtils.formatWalkInfo(LocalContext.current, viewModel.lastWalkDist),
                    color = secondary,
                    fontSize = 14.sp,
                )
            }

            // Onward connection (shared multi-leg route): where you change and
            // the next train. Tap to jump onto it early.
            viewModel.onwardConnection?.let { onward ->
                OnwardConnectionCard(
                    onward = onward,
                    mode = viewModel.currentMode,
                    onTap = { viewModel.trackLeg(onward.legIndex) },
                    modifier = Modifier.padding(top = 16.dp),
                )
            }

            // Formation diagram
            viewModel.formation?.let { formation ->
                FormationDiagram(formation, Modifier.padding(top = 16.dp))
            }

            // Map: hand off to the platform maps app, pinned to the station
            val station = viewModel.currentStation
            if (station?.lat != null && station.lon != null) {
                OutlinedButton(
                    onClick = {
                        val name = Uri.encode(station.name ?: context.getString(CoreR.string.station_fallback))
                        val uri = Uri.parse("geo:${station.lat},${station.lon}?q=${station.lat},${station.lon}($name)")
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                    },
                    modifier = Modifier.padding(top = 16.dp),
                ) {
                    Icon(Icons.Filled.Map, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.show_on_map), modifier = Modifier.padding(start = 6.dp))
                }
            }

            // Save this as a route and keep it going with the app closed via the
            // distance-aware reminder. Asks for background location (disclosure)
            // the first time it's used.
            OutlinedButton(
                onClick = { viewModel.trackCurrentInBackground() },
                modifier = Modifier.padding(top = 12.dp),
            ) {
                Icon(Icons.Filled.Notifications, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(stringResource(R.string.track_in_background), modifier = Modifier.padding(start = 6.dp))
            }

            // One watch button, mirroring iOS: a live watch takes an explicit send
            // of this departure, a closed Garmin the launch/re-sync path. Colour
            // tracks liveness (green = open, amber = closed, grey = paired but off)
            // and a spinner shows while opening. Multiple watches open a picker.
            val watches = viewModel.connectedWatches
            val hasGarmin = viewModel.watchLinks.any { it.type == PhoneWatchType.GARMIN }
            if (watches.isNotEmpty() || hasGarmin) {
                HorizontalDivider(Modifier.padding(top = 16.dp, bottom = 8.dp, start = 24.dp, end = 24.dp))
                var showWatchMenu by remember { mutableStateOf(false) }
                Box {
                    OutlinedButton(onClick = {
                        when {
                            // The watch already tracks this departure; a re-send
                            // would only make it re-enter and buzz again.
                            viewModel.watchTrackingFocused -> {}
                            watches.size > 1 -> showWatchMenu = true
                            else -> viewModel.sendToPrimaryOrOpen()
                        }
                    }) {
                        if (viewModel.watchChecking) {
                            CircularProgressIndicator(strokeWidth = 2.dp, color = palette.platform, modifier = Modifier.size(18.dp))
                        } else {
                            Icon(
                                Icons.Filled.Watch,
                                contentDescription = null,
                                tint = when {
                                    viewModel.watchAlive -> Color(0xFF34C759)
                                    viewModel.watchKnownButDisconnected -> Color(0xFF8E8E93)
                                    else -> Color(0xFFFFB300)
                                },
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        Text(
                            if (viewModel.watchTrackingFocused) stringResource(R.string.tracking_on_watch) else stringResource(R.string.track_on_watch),
                            modifier = Modifier.padding(start = 6.dp),
                        )
                    }
                    DropdownMenu(expanded = showWatchMenu, onDismissRequest = { showWatchMenu = false }) {
                        watches.forEach { watch ->
                            DropdownMenuItem(
                                text = { Text("${watch.name} (${if (watch.type == PhoneWatchType.GARMIN) "Garmin" else "Wear OS"})") },
                                onClick = {
                                    showWatchMenu = false
                                    viewModel.sendToWatch(watch)
                                },
                            )
                        }
                    }
                }
            }
            viewModel.watchSendStatus?.let {
                Text(it, color = secondary, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
            }
        }

        // Back button overlay
        TextButton(
            onClick = { viewModel.exitToStationView() },
            modifier = Modifier.align(Alignment.TopStart).padding(4.dp),
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = stringResource(CoreR.string.back),
                tint = palette.platform,
                modifier = Modifier.size(18.dp),
            )
            Text(stringResource(CoreR.string.back), color = palette.platform, modifier = Modifier.padding(start = 4.dp))
        }
    }
}

@Composable
private fun OnwardConnectionCard(
    onward: OnwardConnection,
    mode: TransportMode,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val leg = onward.leg
    val line = "${leg.category ?: ""}${leg.lineNumber ?: ""}"
    Surface(
        onClick = onTap,
        modifier = modifier.fillMaxWidth(0.92f),
        shape = RoundedCornerShape(12.dp),
        tonalElevation = 3.dp,
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(stringResource(CoreR.string.change_at_fmt, onward.changeStation), color = secondary, fontSize = 12.sp)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(top = 4.dp),
            ) {
                if (line.isNotEmpty()) {
                    Text(
                        line,
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(7.dp))
                            .background(palette.linePill(line, mode))
                            .padding(horizontal = 8.dp, vertical = 2.dp),
                    )
                }
                Text(leg.destName, fontWeight = FontWeight.Medium, maxLines = 1)
            }
            Text(
                stringResource(CoreR.string.min_to_change_fmt, formatDepartureTime(leg.depTs), onward.changeMinutes),
                color = secondary,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

private fun countdownColor(
    focused: FocusedDeparture?,
    nowSeconds: Long,
    palette: AppPalette,
    secondary: Color,
    primary: Color,
): Color {
    if (focused == null) return primary
    val minutesUntil = focused.minutesUntil(nowSeconds)
    return when {
        minutesUntil < -0.5 -> secondary
        minutesUntil < 2.0 -> palette.minutesNow
        else -> palette.minutesSoon
    }
}
