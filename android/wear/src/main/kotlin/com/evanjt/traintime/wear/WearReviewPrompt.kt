package com.evanjt.traintime.wear

import android.app.Activity
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Alert
import androidx.wear.compose.material.dialog.Dialog
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.review.ReviewLauncher

// Timed review ask, watch-sized. "Yes" opens the on-watch Play listing
// (market:// resolves to Wear's own Play Store; same applicationId as the
// phone). Swipe-to-dismiss counts as "Not now".
@Composable
fun WearReviewPrompt(vm: WearViewModel) {
    val activity = LocalContext.current as? Activity
    Dialog(
        showDialog = vm.showReviewPrompt,
        onDismissRequest = { vm.snoozeReview() },
    ) {
        Alert(title = { Text(stringResource(CoreR.string.review_title)) }) {
            item {
                Chip(
                    onClick = {
                        vm.dismissReviewPrompt()
                        activity?.let { ReviewLauncher.openStoreListing(it) }
                    },
                    label = { Text(stringResource(CoreR.string.review_yes)) },
                    colors = ChipDefaults.primaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                Chip(
                    onClick = { vm.snoozeReview() },
                    label = { Text(stringResource(CoreR.string.review_not_now)) },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                )
            }
            item {
                Chip(
                    onClick = { vm.optOutReview() },
                    label = { Text(stringResource(CoreR.string.review_never)) },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                )
            }
        }
    }
}
