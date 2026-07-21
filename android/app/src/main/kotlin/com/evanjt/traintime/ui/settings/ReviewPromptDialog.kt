package com.evanjt.traintime.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR

// Timed review ask. Three outcomes, so the buttons stack in the confirm slot
// (M3 AlertDialog only has two named slots). Dismissing by tapping outside
// counts as "Not now" so the user is never re-asked on the very next launch.
@Composable
fun ReviewPromptDialog(
    onRate: () -> Unit,
    onNotNow: () -> Unit,
    onNever: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onNotNow,
        title = { Text(stringResource(CoreR.string.review_title)) },
        text = { Text(stringResource(R.string.review_body)) },
        confirmButton = {
            Column {
                TextButton(onClick = onRate, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(CoreR.string.review_yes))
                }
                TextButton(onClick = onNotNow, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(CoreR.string.review_not_now))
                }
                TextButton(onClick = onNever, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(CoreR.string.review_never))
                }
            }
        },
    )
}
