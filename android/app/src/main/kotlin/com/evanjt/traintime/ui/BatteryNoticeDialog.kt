package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR

// One-shot heads-up shown when a tracking session starts on a battery-aggressive
// OEM (OnePlus, Xiaomi, Samsung, ...) that hasn't exempted the app. Those
// devices kill the tracking foreground service in the background, so the
// notification silently vanishes. "Open settings" jumps to app settings where
// the user can allow unrestricted battery. Never shown on Pixel/stock or when
// already exempted, and never again once seen.
@Composable
fun BatteryNoticeDialog(
    onOpenSettings: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.battery_notice_title)) },
        text = {
            Text(stringResource(R.string.battery_notice_body))
        },
        confirmButton = {
            TextButton(onClick = onOpenSettings) { Text(stringResource(R.string.battery_notice_action)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(CoreR.string.review_not_now)) }
        },
    )
}
