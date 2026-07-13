package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

// Google Play prominent-disclosure requirement: shown before the system
// "Allow all the time" prompt when the user turns on distance-aware reminders.
// The wording must state that location is collected in the background and name
// the feature, and the user must consent before the OS prompt is launched.
@Composable
fun BackgroundLocationDisclosureDialog(
    onContinue: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Track in the background?") },
        text = {
            Text(
                "TrainTime collects your location to time your route reminder, even " +
                    "when the app is closed or not in use. You can decline, and we'll " +
                    "use your last known location instead.",
            )
        },
        confirmButton = {
            TextButton(onClick = onContinue) { Text("Continue") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Not now") }
        },
    )
}
