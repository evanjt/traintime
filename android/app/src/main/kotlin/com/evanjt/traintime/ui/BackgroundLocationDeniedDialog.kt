package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

// Shown when the user continued past the disclosure but declined "all the time".
// Not a failure: the route is saved and the reminder still fires, it just uses
// the last known location rather than live background updates. Offers a one-tap
// path to grant all-time access later.
@Composable
fun BackgroundLocationDeniedDialog(
    onOpenSettings: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Using your last location") },
        text = {
            Text(
                "That's fine. Your reminder still works, using your last known " +
                    "location instead of live updates. Allow all-time access any " +
                    "time to make it live.",
            )
        },
        confirmButton = {
            TextButton(onClick = onOpenSettings) { Text("Open settings") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Keep as is") }
        },
    )
}
