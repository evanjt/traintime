package com.evanjt.traintime.ui.pending

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.PendingRoute
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val TIME = DateTimeFormatter.ofPattern("HH:mm")

private fun countdownText(depTs: Long, now: Long): String {
    val mins = ((depTs - now) / 60).coerceAtLeast(0)
    return if (mins >= 60) "in ${mins / 60} h ${mins % 60}" else "in $mins min"
}

// Queued shared route: destination, departure countdown, discard. Tap runs
// the resume check (prompts when the train is on the board).
@Composable
fun PendingRouteChip(
    route: PendingRoute,
    nowEpochSeconds: Long,
    notifyTs: Long?,
    onTap: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val leg = route.currentLeg ?: return
    var confirmDiscard by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
        shape = MaterialTheme.shapes.medium,
        tonalElevation = 3.dp,
    ) {
        Row(
            Modifier.clickable(onClick = onTap).padding(start = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                Text(
                    "Route to ${route.finalDestination}",
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    "${leg.category ?: ""}${leg.lineNumber ?: ""} departs " +
                        "${TIME.format(Instant.ofEpochSecond(leg.depTs).atZone(ZoneId.of("Europe/Zurich")))} · " +
                        countdownText(leg.depTs, nowEpochSeconds),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (notifyTs != null && notifyTs > nowEpochSeconds) {
                    Text(
                        "You'll be notified in ${(notifyTs - nowEpochSeconds) / 60} min",
                        style = MaterialTheme.typography.bodySmall,
                        color = LocalAppPalette.current.ahead,
                    )
                }
            }
            IconButton(onClick = { confirmDiscard = true }) {
                Icon(Icons.Default.Close, contentDescription = "Discard route")
            }
        }
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Discard saved route?") },
            text = { Text("The route to ${route.finalDestination} will be forgotten.") },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onDismiss() }) { Text("Discard") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDiscard = false }) { Text("Keep") }
            },
        )
    }
}
