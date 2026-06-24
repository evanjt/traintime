package com.evanjt.traintime.review

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.ktx.launchReview
import com.google.android.play.core.ktx.requestReview
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

// Shared by :app and :wear. Drives the native Play in-app review where it works
// and quietly falls back to the store listing otherwise (some Wear devices and
// any error). The review flow may no-op when Play decides not to show it, which
// is expected, so we never report success or failure to the caller.
object ReviewLauncher {
    fun launch(activity: Activity) {
        val manager = ReviewManagerFactory.create(activity)
        // The flow must run with the Activity on the main thread.
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val info = manager.requestReview()
                manager.launchReview(activity, info)
            } catch (_: Exception) {
                openStoreListing(activity)
            }
        }
    }

    private fun openStoreListing(activity: Activity) {
        val id = activity.packageName
        try {
            activity.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id")),
            )
        } catch (_: ActivityNotFoundException) {
            activity.startActivity(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$id"),
                ),
            )
        }
    }
}
