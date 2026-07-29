package com.evanjt.traintime.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR

// One-shot introduction of the optional background-location upgrade for saved
// route reminders, shown once when a version carrying the feature first runs
// (after the tour). Doubles as the Google Play prominent disclosure: it names
// the feature and states that location is collected in the background, and the
// OS prompt only launches after explicit consent. Declining changes nothing.
@Composable
fun BackgroundLocationIntroDialog(
    onContinue: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.bg_intro_title)) },
        text = {
            Text(stringResource(R.string.bg_intro_body))
        },
        confirmButton = {
            TextButton(onClick = onContinue) { Text(stringResource(R.string.continue_label)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(CoreR.string.review_not_now)) }
        },
    )
}
