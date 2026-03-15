package ch.traintime.phone.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.work.*
import ch.traintime.shared.AppColors
import ch.traintime.phone.MainActivity
import java.net.URLEncoder

class TrainTimeWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            TrainTimeWidgetContent(context)
        }
    }
}

@Composable
fun TrainTimeWidgetContent(context: Context) {
    val result = WidgetStorage.load(context)
    val isStale = result != null &&
        (System.currentTimeMillis() / 1000.0 - result.fetchTime) > 300

    if (result == null || isStale) {
        // Dormant view
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(Color.Black)
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (result?.stationName != null) {
                Text(
                    text = result.stationName,
                    style = TextStyle(
                        color = ColorProvider(Color.Gray),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                Spacer(modifier = GlanceModifier.height(8.dp))
            }
            Text(
                text = "Tap to load",
                style = TextStyle(
                    color = ColorProvider(Color(0xFF55AAFF)),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                ),
                modifier = GlanceModifier.clickable(
                    actionRunCallback<RefreshWidgetAction>()
                )
            )
        }
    } else {
        // Active view
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(Color.Black)
                .padding(12.dp)
        ) {
            // Header
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = result.stationName,
                    style = TextStyle(
                        color = ColorProvider(Color.White),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    modifier = GlanceModifier.defaultWeight()
                )
                Text(
                    text = "\u21BB",
                    style = TextStyle(
                        color = ColorProvider(Color.Gray),
                        fontSize = 14.sp
                    ),
                    modifier = GlanceModifier.clickable(
                        actionRunCallback<RefreshWidgetAction>()
                    )
                )
            }

            Spacer(modifier = GlanceModifier.height(4.dp))

            // Departures
            val size = LocalSize.current
            val maxRows = when {
                size.height < 100.dp -> 2
                size.height < 200.dp -> 4
                else -> 8
            }
            val activeDeps = result.departures.filter { !it.isGone }.take(maxRows)
            if (activeDeps.isEmpty()) {
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = "No departures",
                    style = TextStyle(color = ColorProvider(Color.Gray), fontSize = 12.sp),
                    modifier = GlanceModifier.fillMaxWidth()
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
            } else {
                activeDeps.forEach { dep ->
                    WidgetDepartureRow(dep)
                }
            }
        }
    }
}

@Composable
fun WidgetDepartureRow(dep: WidgetDeparture) {
    val encodedDest = URLEncoder.encode(dep.destination, "UTF-8")
    val deepLink = "traintime://track?destination=$encodedDest&timestamp=${dep.departureTimestamp}"

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .clickable(actionStartActivity<MainActivity>(
                actionParametersOf(
                    ActionParameters.Key<String>("deep_link") to deepLink
                )
            )),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Minutes
        val minColor = when {
            dep.isGone -> Color.Gray
            dep.minutesUntil <= 2 -> Color(AppColors.MINUTES_NOW)
            else -> Color(AppColors.MINUTES_SOON)
        }
        Text(
            text = dep.minutesText,
            style = TextStyle(
                color = ColorProvider(minColor),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            ),
            modifier = GlanceModifier.width(30.dp)
        )

        // Delay
        if (dep.delay > 0) {
            Text(
                text = "+${dep.delay}",
                style = TextStyle(
                    color = ColorProvider(Color(AppColors.DELAY)),
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Medium
                )
            )
        }

        Spacer(modifier = GlanceModifier.width(4.dp))

        // Destination
        Text(
            text = dep.destination,
            style = TextStyle(
                color = ColorProvider(Color.White),
                fontSize = 12.sp
            ),
            maxLines = 1,
            modifier = GlanceModifier.defaultWeight()
        )
    }
}

class WidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TrainTimeWidget()
}
