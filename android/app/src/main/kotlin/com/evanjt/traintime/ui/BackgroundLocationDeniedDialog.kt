package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R

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
        title = { Text(stringResource(R.string.bg_denied_title)) },
        text = {
            Text(stringResource(R.string.bg_denied_body))
        },
        confirmButton = {
            TextButton(onClick = onOpenSettings) { Text(stringResource(R.string.open_settings)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.keep_as_is)) }
        },
    )
}
