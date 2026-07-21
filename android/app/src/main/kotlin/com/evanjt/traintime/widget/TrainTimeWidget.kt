package com.evanjt.traintime.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.state.GlanceStateDefinition
import com.evanjt.traintime.Timing
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.domain.LocaleUtil
import kotlinx.coroutines.flow.first

// Breaker pattern: dormant by default (zero API traffic), tap to activate
// for a 5 min live window with a per-minute countdown, then back to dormant.
// Favourites for the current station are read once per render in
// provideGlance (suspend) and flagged into the rows.
class TrainTimeWidget : GlanceAppWidget() {
    override val stateDefinition: GlanceStateDefinition<WidgetState> = WidgetStateDefinition

    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetStateDefinition.read(context)
        val stationId = snapshot.result?.currentStation?.id
        val favKeys = if (stationId != null) {
            FavouritesStore(context).favouritesForStation(stationId)
                .map { "${it.lineNumber}|${it.destination}" }
                .toSet()
        } else {
            emptySet()
        }

        // The widget renders outside an activity, so the per-app language override
        // doesn't reach it on pre-33 devices. Resolve strings through a context
        // wrapped in the stored language tag, read here (suspend) and captured by
        // the composition. updateAppLanguage triggers updateAll, so a change
        // re-runs provideGlance and re-reads the tag.
        val ctx = LocaleUtil.localised(context, AppPrefs(context).appLanguage.first())

        provideContent {
            val state = currentState<WidgetState>()
            WidgetContent(state, favKeys, ctx)
        }
    }

    companion object {
        val SMALL = DpSize(120.dp, 120.dp)
        val MEDIUM = DpSize(250.dp, 120.dp)
        val LARGE = DpSize(250.dp, 280.dp)

        val ACTIVE_WINDOW_SECONDS = Timing.WIDGET_ACTIVE_WINDOW
    }
}

class TrainTimeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TrainTimeWidget()
}

@Composable
private fun WidgetContent(state: WidgetState, favKeys: Set<String>, ctx: android.content.Context) {
    val now = System.currentTimeMillis() / 1000
    val result = state.result
    val fetchAge = if (result != null) now - result.fetchTime else Long.MAX_VALUE
    val refreshing = state.isRefreshing(now)

    // The age check is a safety net for renders the revert worker did not
    // drive (host re-inflation after reboot, launcher restarts).
    val dormant = result == null || state.dormant || fetchAge > TrainTimeWidget.ACTIVE_WINDOW_SECONDS

    if (dormant) {
        DormantView(result = result, refreshing = refreshing, favKeys = favKeys, nowEpochSeconds = now, ctx = ctx)
    } else {
        ActiveView(
            result = result,
            nowEpochSeconds = now,
            favKeys = favKeys,
            hideFavourites = state.hideFavourites,
            refreshing = refreshing,
            outsideSwitzerland = state.outsideSwitzerland,
            ctx = ctx,
        )
    }
}
