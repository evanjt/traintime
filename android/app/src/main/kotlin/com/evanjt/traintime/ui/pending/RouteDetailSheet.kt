package com.evanjt.traintime.ui.pending

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import com.evanjt.traintime.linePill
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val TIME = DateTimeFormatter.ofPattern("HH:mm")

private fun hhmm(depTs: Long): String =
    TIME.format(Instant.ofEpochSecond(depTs).atZone(ZoneId.of("Europe/Zurich")))

// The train connections of a saved route, current one highlighted. Walk legs
// are omitted: the app tracks trains between stops, not walking. Each trackable
// connection has a departure-reminder switch, and tapping the card tracks it now.
// Platforms come from the live board when close to departure (by leg index).
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RouteDetailSheet(
    route: PendingRoute,
    mode: TransportMode,
    platforms: Map<Int, String>,
    onSetMuted: (Int, Boolean) -> Unit,
    onTrackLeg: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
            Text(
                "Route to ${route.finalDestination}",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 4.dp),
            )
            Text(
                "Tap any connection to track it now. Use its switch to turn the departure reminder off.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 12.dp),
            )
            route.legs.forEachIndexed { index, leg ->
                if (leg.type == LegType.RIDE) {
                    RideLegRow(
                        leg = leg,
                        mode = mode,
                        isCurrent = index == route.cursor,
                        muted = route.isLegMuted(index),
                        platform = platforms[index],
                        onSetTracked = { tracked -> onSetMuted(index, !tracked) },
                        onTrackNow = { onTrackLeg(index); onDismiss() },
                    )
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
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val line = "${leg.category ?: ""}${leg.lineNumber ?: ""}"
    // Every trackable connection reads as a tappable tile; the current one is
    // outlined. Tap anywhere on it to track (the Remind switch keeps its own tap).
    val bg = if (leg.isTrackable) MaterialTheme.colorScheme.surfaceVariant else Color.Transparent
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .then(
                if (isCurrent) {
                    Modifier.border(
                        1.5.dp,
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.6f),
                        RoundedCornerShape(10.dp),
                    )
                } else {
                    Modifier
                },
            )
            .then(if (leg.isTrackable) Modifier.clickable { onTrackNow() } else Modifier)
            .padding(vertical = 8.dp, horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (line.isNotEmpty()) {
            Text(
                line,
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(palette.linePill(line, mode))
                    .padding(horizontal = 7.dp, vertical = 2.dp),
            )
        }
        Column(Modifier.weight(1f).padding(start = 8.dp)) {
            Text("${leg.originName} to ${leg.destName}", fontWeight = FontWeight.Medium, maxLines = 1)
            val times = "${hhmm(leg.depTs)} to ${hhmm(leg.arrTs)}"
            Text(
                if (platform != null) "$times · platform $platform" else times,
                color = secondary,
                fontSize = 12.sp,
            )
            if (isCurrent) {
                Text(
                    "Next connection",
                    color = MaterialTheme.colorScheme.primary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
        if (leg.isTrackable) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Remind", color = secondary, fontSize = 10.sp)
                Switch(checked = !muted, onCheckedChange = onSetTracked)
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = secondary,
                modifier = Modifier.padding(start = 4.dp),
            )
        } else {
            Text("Outside Switzerland", color = secondary, fontSize = 11.sp)
        }
    }
}
