package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R
import com.evanjt.traintime.ui.adaptive.BoardPicker

// A tap on a board picker locked by tracking offers to stop, then opens it.
@Composable
fun StopToChangeDialog(
    picker: BoardPicker,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val title = when (picker) {
        BoardPicker.Station -> R.string.stop_to_change_station_title
        is BoardPicker.Mode -> R.string.stop_to_change_mode_title
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(title)) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.stop_tracking)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.switch_tracking_cancel)) }
        },
    )
}
