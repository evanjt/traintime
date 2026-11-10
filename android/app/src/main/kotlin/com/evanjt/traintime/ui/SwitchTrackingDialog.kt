package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R

// A board tap on another departure while one is tracked replaces the session.
@Composable
fun SwitchTrackingDialog(
    line: String,
    destination: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.switch_tracking_title_fmt, line, destination)) },
        text = { Text(stringResource(R.string.switch_tracking_body)) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.switch_tracking_confirm)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.switch_tracking_cancel)) }
        },
    )
}
