package com.evanjt.traintime.wear

import android.app.Activity
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Alert
import androidx.wear.compose.material.dialog.Dialog
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
        Alert(title = { Text("Enjoying TrainTime?") }) {
            item {
                Chip(
                    onClick = {
                        vm.dismissReviewPrompt()
                        activity?.let { ReviewLauncher.openStoreListing(it) }
                    },
                    label = { Text("Yes, rate it") },
                    colors = ChipDefaults.primaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                Chip(
                    onClick = { vm.snoozeReview() },
                    label = { Text("Not now") },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                )
            }
            item {
                Chip(
                    onClick = { vm.optOutReview() },
                    label = { Text("Don't ask again") },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                )
            }
        }
    }
}
