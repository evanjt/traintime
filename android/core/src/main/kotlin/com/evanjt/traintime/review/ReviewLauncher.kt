package com.evanjt.traintime.review

import android.app.Activity
import android.content.Intent
import android.net.Uri

// Shared by :app and :wear. Every rating path opens the store listing: the
// Play in-app review API can complete without showing any UI (sideloads,
// quota), so a tap on "Rate" would silently do nothing. The listing always
// opens. Mirrors iOS, which opens the write-review URL for the same reason.
object ReviewLauncher {
    fun openStoreListing(activity: Activity) {
        val id = activity.packageName
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id"))
        val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$id"))
        // No Play app falls back to the browser; a device with neither must not crash.
        runCatching { activity.startActivity(market) }
            .onFailure { runCatching { activity.startActivity(web) } }
    }
}
