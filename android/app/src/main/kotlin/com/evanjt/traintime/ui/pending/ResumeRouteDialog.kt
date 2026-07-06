package com.evanjt.traintime.ui.pending

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import com.evanjt.traintime.data.model.Departure

// The queued route's train is on the live board. One tap starts tracking.
@Composable
fun ResumeRouteDialog(
    destination: String,
    departure: Departure,
    onTrack: () -> Unit,
    onLater: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onLater,
        title = { Text("Resume route to $destination?") },
        text = {
            Text(
                "${departure.lineNumber} to ${departure.destination} departs " +
                    "in ${departure.minutesUntil.coerceAtLeast(0)} min" +
                    (departure.platform.takeIf { it.isNotEmpty() }?.let { " from platform $it" } ?: ""),
            )
        },
        confirmButton = {
            TextButton(onClick = onTrack) { Text("Track") }
        },
        dismissButton = {
            TextButton(onClick = onLater) { Text("Later") }
        },
    )
}
