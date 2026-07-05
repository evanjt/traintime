package com.evanjt.traintime.review

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.ktx.launchReview
import com.google.android.play.core.ktx.requestReview
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

// Shared by :app and :wear. Two paths with different guarantees: the native
// Play in-app review may silently show nothing (sideloads, quota), so it is
// only used after the timed prompt's explicit "Yes" on the phone; every manual
// "Rate" button goes straight to the store listing, which always opens.
object ReviewLauncher {
    fun launchInAppReview(activity: Activity) {
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

    fun openStoreListing(activity: Activity) {
        val id = activity.packageName
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id"))
        val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$id"))
        // No Play app falls back to the browser; a device with neither must not crash.
        runCatching { activity.startActivity(market) }
            .onFailure { runCatching { activity.startActivity(web) } }
    }
}
