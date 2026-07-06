package com.evanjt.traintime.ui.pending

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
// connection has a departure-reminder switch and a "Track now". Platforms come
// from the live board when close to departure (platforms map by leg index).
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
                "Each connection can send a reminder before it departs. Turn one off, or track any now.",
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
    val bg = if (isCurrent) MaterialTheme.colorScheme.surfaceVariant else Color.Transparent
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .padding(vertical = 8.dp, horizontal = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
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
            }
            if (leg.isTrackable) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Remind", color = secondary, fontSize = 10.sp)
                    Switch(checked = !muted, onCheckedChange = onSetTracked)
                }
            } else {
                Text("Outside Switzerland", color = secondary, fontSize = 11.sp)
            }
        }
        if (leg.isTrackable) {
            Row(
                Modifier.fillMaxWidth().padding(top = 2.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (isCurrent) "Next connection" else "",
                    color = secondary,
                    fontSize = 11.sp,
                )
                TextButton(onClick = onTrackNow) { Text("Track now") }
            }
        }
    }
}
