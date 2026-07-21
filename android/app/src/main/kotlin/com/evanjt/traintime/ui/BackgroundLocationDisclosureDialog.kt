package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR

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
        title = { Text(stringResource(R.string.bg_track_title)) },
        text = {
            Text(stringResource(R.string.bg_track_body))
        },
        confirmButton = {
            TextButton(onClick = onContinue) { Text(stringResource(R.string.continue_label)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(CoreR.string.review_not_now)) }
        },
    )
}
