package com.evanjt.traintime.widget.actions

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import androidx.work.WorkManager
import com.evanjt.traintime.widget.TrainTimeWidget
import com.evanjt.traintime.widget.WidgetStateDefinition
import com.evanjt.traintime.widget.work.WidgetTickWorker

// Flips the favourites-grouping display mode. No network — toggles a flag.
class ToggleFavouritesAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        WidgetStateDefinition.update(context) { it.copy(hideFavourites = !it.hideFavourites) }
        TrainTimeWidget().updateAll(context)
    }
}

// Drops the widget back to dormant at once, cancelling the pending live-window
// ticks. The next Refresh re-activates it.
class StopAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        WorkManager.getInstance(context).cancelUniqueWork(WidgetTickWorker.UNIQUE_NAME)
        WidgetStateDefinition.update(context) { it.copy(dormant = true, refreshStartedAt = 0) }
        TrainTimeWidget().updateAll(context)
    }
}
