package com.evanjt.traintime.ui.pending

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.ui.TrackingStatus

// The queued route's train is on the live board. One tap starts tracking.
// walkText/slackText, when present, are the succinct reminder readout: walk time
// then the ahead/behind margin on its own line, so the user sees at a glance
// whether they can still make it.
@Composable
fun ResumeRouteDialog(
    destination: String,
    departure: Departure,
    walkText: String?,
    slackText: String?,
    slackStatus: TrackingStatus?,
    onTrack: () -> Unit,
    onLater: () -> Unit,
) {
    val palette = LocalAppPalette.current
    AlertDialog(
        onDismissRequest = onLater,
        title = { Text("Resume route to $destination?") },
        text = {
            Column {
                Text(
                    "${departure.lineNumber} to ${departure.destination} departs " +
                        "in ${departure.minutesUntil.coerceAtLeast(0)} min" +
                        (departure.platform.takeIf { it.isNotEmpty() }?.let { " from platform $it" } ?: ""),
                )
                if (walkText != null) {
                    Text(walkText, color = palette.platform)
                }
                if (slackText != null) {
                    val color = when (slackStatus) {
                        TrackingStatus.AHEAD -> palette.ahead
                        TrackingStatus.BEHIND -> palette.behind
                        else -> palette.onTime
                    }
                    Text(slackText, color = color, fontWeight = FontWeight.SemiBold)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onTrack) { Text("Track") }
        },
        dismissButton = {
            TextButton(onClick = onLater) { Text("Later") }
        },
    )
}
