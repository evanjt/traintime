package com.evanjt.traintime.widget.work

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

// Fallback refresh path when the location foreground service cannot be
// started: refresh from the cached location tiers only.
class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        WidgetRefresher.refresh(applicationContext, location = null)
        return Result.success()
    }

    companion object {
        const val UNIQUE_NAME = "widget_refresh"
    }
}
