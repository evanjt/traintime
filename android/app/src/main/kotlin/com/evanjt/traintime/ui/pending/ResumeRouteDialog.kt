package com.evanjt.traintime.ui.pending

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.Departure

// The queued route's train is on the live board. One tap starts tracking.
// walkMin/bufferMin, when present, show the reminder's travel-time + buffer split.
@Composable
fun ResumeRouteDialog(
    destination: String,
    departure: Departure,
    walkMin: Int?,
    bufferMin: Int?,
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
                if (walkMin != null && bufferMin != null) {
                    Text(
                        buildAnnotatedString {
                            append("Reminder: ~")
                            withStyle(SpanStyle(color = palette.platform)) { append("$walkMin min walk") }
                            append(" + ")
                            withStyle(SpanStyle(color = palette.amber)) { append("$bufferMin min buffer") }
                            append(" before")
                        },
                    )
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
