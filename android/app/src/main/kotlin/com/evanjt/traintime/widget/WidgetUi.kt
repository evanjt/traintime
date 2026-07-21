package com.evanjt.traintime.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.CircularProgressIndicator
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.widget.actions.RefreshAction
import com.evanjt.traintime.widget.actions.StopAction
import com.evanjt.traintime.widget.actions.SwitchModeAction
import com.evanjt.traintime.widget.actions.SwitchStationAction
import com.evanjt.traintime.widget.actions.ToggleFavouritesAction

private fun maxRows(width: androidx.compose.ui.unit.Dp): Int =
    if (width >= TrainTimeWidget.LARGE.width) 7 else 3

private fun isSmall(width: androidx.compose.ui.unit.Dp): Boolean =
    width < TrainTimeWidget.MEDIUM.width

private fun trackIntent(dep: WidgetDeparture): Intent =
    Intent(
        Intent.ACTION_VIEW,
        Uri.parse("traintime://track?destination=${Uri.encode(dep.destination)}&timestamp=${dep.departureTimestamp}"),
    )

// ----- Dormant -----

@Composable
internal fun DormantView(
    result: WidgetFetchResult?,
    refreshing: Boolean,
    favKeys: Set<String>,
    nowEpochSeconds: Long,
    ctx: Context,
) {
    val station = result?.currentStation
    if (station == null || station.departures.isEmpty()) {
        SimpleDormantView(stationName = station?.name, refreshing = refreshing, ctx = ctx)
    } else {
        StaleDormantView(result = result, station = station, favKeys = favKeys, nowEpochSeconds = nowEpochSeconds, refreshing = refreshing, ctx = ctx)
    }
}

@Composable
private fun SimpleDormantView(stationName: String?, refreshing: Boolean, ctx: Context) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetColors.background)
            .clickable(actionRunCallback<RefreshAction>())
            .padding(12.dp),
    ) {
        Text("TrainTime", style = TextStyle(color = WidgetColors.secondary, fontSize = 12.sp, fontWeight = FontWeight.Medium))
        if (stationName != null) {
            Text(
                stationName,
                style = TextStyle(color = WidgetColors.secondary, fontSize = 13.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
                modifier = GlanceModifier.padding(top = 2.dp),
            )
        }
        Spacer(GlanceModifier.height(8.dp))
        RefreshChip(refreshing, ctx)
    }
}

@Composable
private fun StaleDormantView(
    result: WidgetFetchResult,
    station: WidgetStation,
    favKeys: Set<String>,
    nowEpochSeconds: Long,
    refreshing: Boolean,
    ctx: Context,
) {
    val size = LocalSize.current
    // Fewer rows than the active view: the dormant view also carries the "as of"
    // header and the Refresh chip, so leave room for them.
    val limit = (maxRows(size.width) - 2).coerceAtLeast(1)
    val rows = displayRows(station.departures, favKeys, nowEpochSeconds, limit, hideFavourites = false)
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetColors.background)
            .padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
            Text(
                station.name,
                style = TextStyle(color = WidgetColors.secondary, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight(),
            )
            Text(
                ctx.getString(R.string.as_of_fmt, asOfText(result.fetchTime)),
                style = TextStyle(color = WidgetColors.secondary, fontSize = 10.sp),
            )
        }
        Divider()
        // Weighted so it absorbs the spare height and the chip below stays pinned
        // to the bottom (and fully visible) instead of being pushed off-widget.
        Column(modifier = GlanceModifier.defaultWeight().fillMaxWidth()) {
            rows.forEach { dep ->
                StaleRow(dep, favKeys, nowEpochSeconds, isSmall(size.width), ctx)
            }
        }
        Box(modifier = GlanceModifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            RefreshChip(refreshing, ctx)
        }
    }
}

@Composable
private fun StaleRow(dep: WidgetDeparture, favKeys: Set<String>, now: Long, small: Boolean, ctx: Context) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 3.dp),
    ) {
        Text(
            dep.clockTimeText,
            style = TextStyle(color = WidgetColors.secondary, fontSize = 13.sp, fontWeight = FontWeight.Medium),
            modifier = GlanceModifier.width(if (small) 40.dp else 70.dp),
        )
        if (!small) {
            Text(
                lineLabel(dep, ctx),
                style = TextStyle(color = WidgetColors.secondary, fontSize = 12.sp, fontWeight = FontWeight.Medium),
                maxLines = 1,
                modifier = GlanceModifier.width(34.dp),
            )
        }
        Text(
            dep.destination,
            style = TextStyle(color = WidgetColors.secondary, fontSize = 13.sp),
            maxLines = 1,
            modifier = GlanceModifier.defaultWeight(),
        )
        if (dep.favKey in favKeys) StarGlyph()
    }
}

// ----- Active -----

@Composable
internal fun ActiveView(
    result: WidgetFetchResult,
    nowEpochSeconds: Long,
    favKeys: Set<String>,
    hideFavourites: Boolean,
    refreshing: Boolean,
    outsideSwitzerland: Boolean = false,
    ctx: Context,
) {
    val size = LocalSize.current
    val small = isSmall(size.width)
    val rowBudget = maxRows(size.width)
    val station = result.currentStation
    val stations = result.stations(result.selectedMode)

    val favRows = if (hideFavourites) emptyList() else
        WidgetFavourites.block(station?.departures ?: emptyList(), favKeys, nowEpochSeconds).take(rowBudget)
    val regularRows = (station?.departures ?: emptyList())
        .filter { !it.isGone(nowEpochSeconds) }
        .take(rowBudget - favRows.size)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetColors.background)
            .padding(12.dp),
    ) {
        // Header
        Row(verticalAlignment = Alignment.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
            if (!small && result.availableModes.size > 1) {
                HeaderGlyph(ctx.getString(result.selectedMode.labelRes), WidgetColors.accent, actionRunCallback<SwitchModeAction>())
                Spacer(GlanceModifier.width(4.dp))
            }
            val stationLabel = station?.name ?: ctx.getString(CoreR.string.station_fallback)
            val label = if (stations.size > 1) {
                "$stationLabel  ${result.selectedStationIndex.coerceAtMost(stations.size - 1) + 1}/${stations.size}"
            } else {
                stationLabel
            }
            val stationModifier = GlanceModifier.defaultWeight().let {
                if (stations.size > 1) it.clickable(actionRunCallback<SwitchStationAction>()) else it
            }
            Text(
                label,
                style = TextStyle(color = WidgetColors.onSurface, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
                modifier = stationModifier,
            )
            if (!small && favKeys.isNotEmpty()) {
                HeaderGlyph(
                    if (hideFavourites) "☆" else "★",
                    if (hideFavourites) WidgetColors.secondary else WidgetColors.favouriteStar,
                    actionRunCallback<ToggleFavouritesAction>(),
                )
            }
            if (!small) {
                HeaderGlyph("■", WidgetColors.secondary, actionRunCallback<StopAction>())
            }
            if (refreshing) {
                CircularProgressIndicator(
                    color = WidgetColors.secondary,
                    modifier = GlanceModifier.size(18.dp),
                )
            } else {
                HeaderGlyph("↻", WidgetColors.secondary, actionRunCallback<RefreshAction>())
            }
        }

        Divider()

        if (favRows.isEmpty() && regularRows.isEmpty()) {
            val emptyMessage = if (outsideSwitzerland) ctx.getString(CoreR.string.outside_switzerland) else ctx.getString(R.string.no_departures)
            Box(GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(emptyMessage, style = TextStyle(color = WidgetColors.secondary, fontSize = 12.sp))
            }
        } else {
            favRows.forEach { dep -> DepartureRow(dep, isFavourite = true, favKeys, nowEpochSeconds, small, result.selectedMode, ctx) }
            if (favRows.isNotEmpty() && regularRows.isNotEmpty()) {
                Box(
                    GlanceModifier
                        .fillMaxWidth()
                        .height(2.dp)
                        .padding(vertical = 0.dp)
                        .background(WidgetColors.favouriteSeparator),
                ) {}
            }
            regularRows.forEach { dep ->
                DepartureRow(dep, isFavourite = dep.favKey in favKeys, favKeys, nowEpochSeconds, small, result.selectedMode, ctx)
            }
        }
    }
}

@Composable
private fun DepartureRow(
    dep: WidgetDeparture,
    isFavourite: Boolean,
    favKeys: Set<String>,
    now: Long,
    small: Boolean,
    mode: TransportMode,
    ctx: Context,
) {
    val minutesColor = when {
        dep.isGone(now) -> WidgetColors.secondary
        dep.minutesUntil(now) <= 2 -> WidgetColors.minutesNow
        else -> WidgetColors.minutesSoon
    }
    val rowBg = if (isFavourite) {
        GlanceModifier.background(WidgetColors.favouriteBackground).cornerRadius(6.dp)
    } else {
        GlanceModifier
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 1.dp)
            .then(rowBg)
            .clickable(actionStartActivity(trackIntent(dep)))
            .padding(horizontal = 4.dp, vertical = 3.dp),
    ) {
        Text(
            minutesLabel(dep, now, ctx),
            style = TextStyle(color = minutesColor, fontSize = if (small) 15.sp else 18.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
            modifier = GlanceModifier.width(if (small) 30.dp else 38.dp),
        )
        if (!small) {
            // Fixed-width slot so the line number and destination columns line up
            // whether or not a delay badge is present (badge width varies by digits).
            Box(
                modifier = GlanceModifier.width(38.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (dep.delay > 0) {
                    Text(
                        "+${dep.delay}",
                        style = TextStyle(color = ColorProvider(androidx.compose.ui.graphics.Color.White), fontSize = 11.sp, fontWeight = FontWeight.Medium),
                        modifier = GlanceModifier
                            .background(WidgetColors.delay)
                            .cornerRadius(8.dp)
                            .padding(horizontal = 5.dp, vertical = 1.dp),
                    )
                }
            }
            Spacer(GlanceModifier.width(4.dp))
        }
        // Line number as a filled pill (white text), in a fixed slot so the
        // destination column still lines up.
        Box(
            modifier = GlanceModifier.width(if (small) 30.dp else 44.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            val label = lineLabel(dep, ctx)
            if (label.isNotEmpty()) {
                Text(
                    label,
                    style = TextStyle(
                        color = ColorProvider(androidx.compose.ui.graphics.Color.White),
                        fontSize = if (small) 11.sp else 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    maxLines = 1,
                    modifier = GlanceModifier
                        .background(WidgetColors.linePill(dep.lineNumber, mode))
                        .cornerRadius(5.dp)
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
            }
        }
        Spacer(GlanceModifier.width(6.dp))
        Text(
            dep.destination,
            style = TextStyle(color = WidgetColors.onSurface, fontSize = if (small) 13.sp else 14.sp),
            maxLines = 1,
            modifier = GlanceModifier.defaultWeight(),
        )
        if (isFavourite) StarGlyph()
    }
}

// ----- Shared bits -----

@Composable
private fun Divider() {
    Box(
        GlanceModifier
            .fillMaxWidth()
            .height(1.dp)
            .padding(vertical = 0.dp)
            .background(WidgetColors.divider),
    ) {}
}

@Composable
private fun HeaderGlyph(text: String, color: ColorProvider, action: androidx.glance.action.Action) {
    Text(
        text,
        style = TextStyle(color = color, fontSize = 15.sp, fontWeight = FontWeight.Medium),
        modifier = GlanceModifier.clickable(action).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
private fun StarGlyph() {
    Text("★", style = TextStyle(color = WidgetColors.favouriteStar, fontSize = 11.sp))
}

@Composable
private fun RefreshChip(refreshing: Boolean, ctx: Context) {
    val white = ColorProvider(androidx.compose.ui.graphics.Color.White)
    Box(
        modifier = GlanceModifier
            .background(WidgetColors.accent)
            .cornerRadius(14.dp)
            .clickable(actionRunCallback<RefreshAction>())
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        if (refreshing) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(color = white, modifier = GlanceModifier.size(14.dp))
                Spacer(GlanceModifier.width(6.dp))
                Text(ctx.getString(R.string.updating), style = TextStyle(color = white, fontSize = 12.sp, fontWeight = FontWeight.Medium))
            }
        } else {
            Text(ctx.getString(R.string.refresh_label), style = TextStyle(color = white, fontSize = 12.sp, fontWeight = FontWeight.Medium))
        }
    }
}

private fun displayRows(
    departures: List<WidgetDeparture>,
    favKeys: Set<String>,
    now: Long,
    limit: Int,
    hideFavourites: Boolean,
): List<WidgetDeparture> {
    if (limit <= 0) return emptyList()
    val favs = if (hideFavourites) emptyList() else WidgetFavourites.block(departures, favKeys, now).take(limit)
    val regular = departures.filter { !it.isGone(now) }.take(limit - favs.size)
    return favs + regular
}

private fun lineLabel(dep: WidgetDeparture, ctx: Context): String = when {
    dep.lineNumber.isNotEmpty() -> dep.lineNumber
    dep.platform.isNotEmpty() -> ctx.getString(R.string.platform_short_fmt, dep.platform)
    else -> ""
}

// Render-time localisation of the gone/now/minutes label. Resolved here (not in
// stored state) through the passed localised context so a language change applies
// on the next render. The minute maths lives in WidgetDeparture.minutesUntil.
private fun minutesLabel(dep: WidgetDeparture, now: Long, ctx: Context): String {
    val m = dep.minutesUntil(now)
    return when {
        m < 0 -> ctx.getString(CoreR.string.row_gone)
        m == 0 -> ctx.getString(CoreR.string.row_now)
        else -> "$m'"
    }
}

private fun asOfText(fetchTimeSeconds: Long): String {
    val time = java.time.Instant.ofEpochSecond(fetchTimeSeconds).atZone(java.time.ZoneId.systemDefault())
    return "%02d:%02d".format(time.hour, time.minute)
}
