package com.evanjt.traintime.ui.pending

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R

// A new shared trip arrived while another route is queued.
@Composable
fun ReplaceRouteDialog(
    destination: String,
    onReplace: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.replace_route_title)) },
        text = { Text(stringResource(R.string.replace_route_body_fmt, destination)) },
        confirmButton = {
            TextButton(onClick = onReplace) { Text(stringResource(R.string.replace)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.keep_existing)) }
        },
    )
}
