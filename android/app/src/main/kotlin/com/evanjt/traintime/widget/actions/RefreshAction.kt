package com.evanjt.traintime.widget.actions

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.evanjt.traintime.widget.TrainTimeWidget
import com.evanjt.traintime.widget.WidgetStateDefinition
import com.evanjt.traintime.widget.work.WidgetRefreshService
import com.evanjt.traintime.widget.work.WidgetRefreshWorker

// Tap-to-activate. The broadcast budget is too small for GPS + two
// network calls, so flip the spinner on and hand off: preferably to the
// location foreground service (live fix), else to WorkManager (cached
// location tiers).
class RefreshAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val now = System.currentTimeMillis() / 1000
        WidgetStateDefinition.update(context) { it.copy(refreshStartedAt = now) }
        TrainTimeWidget().updateAll(context)

        if (!WidgetRefreshService.start(context)) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                WidgetRefreshWorker.UNIQUE_NAME,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<WidgetRefreshWorker>().build(),
            )
        }
    }
}
