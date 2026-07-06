package com.evanjt.traintime.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Switch
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.ToggleChip
import androidx.wear.compose.material.ToggleChipDefaults
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val TIME = DateTimeFormatter.ofPattern("HH:mm")

private fun hhmm(depTs: Long): String =
    TIME.format(Instant.ofEpochSecond(depTs).atZone(ZoneId.of("Europe/Zurich")))

// The train connections of a saved route (Wear peer of the phone's
// RouteDetailSheet): the ride legs in order, the current one highlighted, each
// trackable ride leg with a remind toggle and a "Track now". Walk legs are
// omitted (the app tracks trains, not walking). Platforms come from the live
// board when close to departure (platforms map by leg index).
@Composable
fun WearRouteScreen(vm: WearViewModel, onDismiss: () -> Unit) {
    val route = vm.pendingRoute
    val platforms = vm.routeLegPlatforms
    LaunchedEffect(route) { route?.let { vm.loadRoutePlatforms(it) } }
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
            if (route == null) {
                item {
                    Text(
                        "No saved route",
                        color = MaterialTheme.colors.onSurfaceVariant,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                return@ScalingLazyColumn
            }

            item {
                Text(
                    "Route to ${route.finalDestination}",
                    color = MaterialTheme.colors.onBackground,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 2.dp),
                )
            }
            item {
                Text(
                    "Each connection can send a reminder before it departs. Turn one off, or track any now.",
                    color = MaterialTheme.colors.onSurfaceVariant,
                    fontSize = 10.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                )
            }

            route.legs.forEachIndexed { index, leg ->
                if (leg.type == LegType.RIDE) {
                    item {
                        RideLegRow(
                            leg = leg,
                            mode = vm.currentMode,
                            isCurrent = index == route.cursor,
                            muted = route.isLegMuted(index),
                            platform = platforms[index],
                            onSetTracked = { tracked -> vm.setLegMuted(index, !tracked) },
                            onTrackNow = { vm.trackLeg(index); onDismiss() },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RideLegRow(
    leg: RouteLeg,
    mode: TransportMode,
    isCurrent: Boolean,
    muted: Boolean,
    platform: String?,
    onSetTracked: (Boolean) -> Unit,
    onTrackNow: () -> Unit,
) {
    val palette = LocalWearPalette.current
    val secondary = MaterialTheme.colors.onSurfaceVariant
    val line = "${leg.category ?: ""}${leg.lineNumber ?: ""}"
    val bg = if (isCurrent) MaterialTheme.colors.surface else Color.Transparent
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .padding(horizontal = 8.dp, vertical = 6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (line.isNotEmpty()) {
                Text(
                    line,
                    color = Color.White,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(palette.linePill(line, mode))
                        .padding(horizontal = 6.dp, vertical = 1.dp),
                )
            }
            Column(Modifier.weight(1f).padding(start = 6.dp)) {
                Text(
                    "${leg.originName} → ${leg.destName}",
                    color = MaterialTheme.colors.onBackground,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val times = "${hhmm(leg.depTs)} → ${hhmm(leg.arrTs)}"
                Text(
                    if (platform != null) "$times · platform $platform" else times,
                    color = secondary,
                    fontSize = 10.sp,
                )
            }
        }
        if (leg.isTrackable) {
            ToggleChip(
                checked = !muted,
                onCheckedChange = { checked -> onSetTracked(checked) },
                label = { Text("Remind", fontSize = 12.sp) },
                secondaryLabel = { Text("before it departs", fontSize = 10.sp) },
                toggleControl = { Switch(checked = !muted) },
                colors = ToggleChipDefaults.toggleChipColors(),
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            )
            Chip(
                onClick = onTrackNow,
                label = { Text("Track now", fontSize = 12.sp) },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
            )
        } else {
            Text(
                "Outside Switzerland",
                color = secondary,
                fontSize = 10.sp,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}
