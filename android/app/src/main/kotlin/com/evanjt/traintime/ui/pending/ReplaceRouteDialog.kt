package com.evanjt.traintime.ui.pending

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

// A new shared trip arrived while another route is queued.
@Composable
fun ReplaceRouteDialog(
    destination: String,
    onReplace: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Replace queued route?") },
        text = { Text("You already have a route saved. Replace it with the trip to $destination?") },
        confirmButton = {
            TextButton(onClick = onReplace) { Text("Replace") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Keep existing") }
        },
    )
}
