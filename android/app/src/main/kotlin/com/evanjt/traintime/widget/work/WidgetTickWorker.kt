package com.evanjt.traintime.widget.work

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.evanjt.traintime.Timing
import com.evanjt.traintime.widget.TrainTimeWidget
import com.evanjt.traintime.widget.WidgetStateDefinition
import java.time.Duration

// Self-chaining: re-renders the widget each minute so the countdown ticks,
// re-enqueues itself, and flips to dormant once the active window lapses.
// A Doze-delayed run only means the stale view lingers a little longer; the
// render-time age check is the safety net.
class WidgetTickWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val state = WidgetStateDefinition.read(applicationContext)
        val result = state.result
        if (state.dormant || result == null) return Result.success()

        val now = System.currentTimeMillis() / 1000
        val age = now - result.fetchTime

        if (age >= Timing.WIDGET_ACTIVE_WINDOW) {
            WidgetStateDefinition.update(applicationContext) { it.copy(dormant = true) }
            TrainTimeWidget().updateAll(applicationContext)
            return Result.success()
        }

        TrainTimeWidget().updateAll(applicationContext)
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            UNIQUE_NAME,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<WidgetTickWorker>()
                .setInitialDelay(Duration.ofSeconds(60))
                .build(),
        )
        return Result.success()
    }

    companion object {
        const val UNIQUE_NAME = "widget_tick"
    }
}
