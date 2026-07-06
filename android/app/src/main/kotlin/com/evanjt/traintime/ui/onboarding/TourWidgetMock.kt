package com.evanjt.traintime.ui.onboarding

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.widget.TrainTimeWidgetReceiver

// A pure-Compose replica of the Glance widget's active view (widget/WidgetUi.kt
// ActiveView). Glance renders RemoteViews and can't paint inside the app, so the
// tour shows this look-alike. Colours mirror widget/WidgetColors.kt, keep them
// in sync if the real widget restyles.
private data class WidgetMockColors(
    val background: Color,
    val onSurface: Color,
    val secondary: Color,
    val divider: Color,
    val favouriteBackground: Color,
    val favouriteSeparator: Color,
    val favouriteStar: Color,
    val delay: Color,
    val minutesNow: Color,
    val minutesSoon: Color,
    val accent: Color,
    val lineLongDistance: Color,
    val lineRegional: Color,
)

// Follow the app's effective theme (which the in-app appearance override drives
// through MaterialTheme), not the raw system setting, so the preview matches what
// the user currently sees.
@Composable
private fun widgetMockColors(): WidgetMockColors =
    if (MaterialTheme.colorScheme.background.luminance() < 0.5f) {
        WidgetMockColors(
            background = Color.Black,
            onSurface = Color.White,
            secondary = Color(0xFFAAAAAA),
            divider = Color(0xFF333333),
            favouriteBackground = Color(0xFF332800),
            favouriteSeparator = Color(0xFF998800),
            favouriteStar = Color(0xFFFFD700),
            delay = Color(0xFFFF5500),
            minutesNow = Color(0xFFFFFF00),
            minutesSoon = Color(0xFF00FF00),
            accent = Color(0xFF55AAFF),
            lineLongDistance = Color(0xFFE63950),
            lineRegional = Color(0xFF2E86E0),
        )
    } else {
        WidgetMockColors(
            background = Color.White,
            onSurface = Color.Black,
            secondary = Color(0xFF6D6D72),
            divider = Color(0xFFD1D1D6),
            favouriteBackground = Color(0xFFF7EFD2),
            favouriteSeparator = Color(0xFFB89B00),
            favouriteStar = Color(0xFFA07800),
            delay = Color(0xFFC73E00),
            minutesNow = Color(0xFFB58900),
            minutesSoon = Color(0xFF1E7D32),
            accent = Color(0xFF0061C2),
            lineLongDistance = Color(0xFFD5001C),
            lineRegional = Color(0xFF0061C2),
        )
    }

private val LONG_DISTANCE_PREFIXES =
    setOf("IC", "ICE", "EC", "ICN", "IR", "RJ", "RJX", "TGV", "EN", "NJ", "PE")

private fun WidgetMockColors.linePill(line: String): Color {
    val prefix = line.takeWhile { it.isLetter() }.uppercase()
    return if (prefix in LONG_DISTANCE_PREFIXES) lineLongDistance else lineRegional
}

private data class MockRow(
    val minutes: String,
    val delay: Int,
    val line: String,
    val destination: String,
    val soon: Boolean,
    val favourite: Boolean,
)

@Composable
fun TourWidgetMock(modifier: Modifier = Modifier) {
    val c = widgetMockColors()
    Column(
        modifier = modifier
            .width(260.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(c.background)
            .padding(12.dp),
    ) {
        // Header
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Train", color = c.accent, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.width(6.dp))
            Text(
                "Bern Bahnhof",
                color = c.onSurface,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            Text("★", color = c.favouriteStar, fontSize = 13.sp)
            Spacer(Modifier.width(8.dp))
            Text("■", color = c.secondary, fontSize = 13.sp)
            Spacer(Modifier.width(8.dp))
            Text("↻", color = c.secondary, fontSize = 14.sp)
        }
        Spacer(Modifier.height(6.dp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(c.divider))
        Spacer(Modifier.height(4.dp))

        WidgetRow(c, MockRow("4'", 0, "IC1", "Zürich HB", soon = true, favourite = true))
        Spacer(Modifier.height(2.dp))
        Box(Modifier.fillMaxWidth().height(2.dp).background(c.favouriteSeparator))
        Spacer(Modifier.height(4.dp))
        WidgetRow(c, MockRow("6'", 3, "IC8", "Brig", soon = false, favourite = false))
        WidgetRow(c, MockRow("9'", 0, "IR15", "Luzern", soon = false, favourite = false))
    }
}

@Composable
private fun WidgetRow(c: WidgetMockColors, row: MockRow) {
    val rowMod = if (row.favourite) {
        Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(c.favouriteBackground)
    } else {
        Modifier.fillMaxWidth()
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = rowMod.padding(horizontal = 4.dp, vertical = 4.dp),
    ) {
        Text(
            row.minutes,
            color = if (row.soon) c.minutesNow else c.minutesSoon,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.width(34.dp),
        )
        Box(Modifier.width(34.dp)) {
            if (row.delay > 0) {
                Text(
                    "+${row.delay}",
                    color = Color.White,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(c.delay)
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
            }
        }
        Text(
            row.line,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .clip(RoundedCornerShape(5.dp))
                .background(c.linePill(row.line))
                .padding(horizontal = 5.dp, vertical = 1.dp),
        )
        Spacer(Modifier.width(6.dp))
        Text(
            row.destination,
            color = c.onSurface,
            fontSize = 14.sp,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        if (row.favourite) Text("★", color = c.favouriteStar, fontSize = 11.sp)
    }
}

// Android lets an app ask the launcher to pin its widget (API 26+). Most
// launchers support it; where they don't, fall back to a hint. iOS has no
// equivalent, WidgetKit can't add a widget programmatically.
@Composable
fun AddWidgetButton(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val manager = AppWidgetManager.getInstance(context)
    if (manager.isRequestPinAppWidgetSupported) {
        Button(
            onClick = {
                val provider = ComponentName(context, TrainTimeWidgetReceiver::class.java)
                runCatching { manager.requestPinAppWidget(provider, null, null) }
            },
            modifier = modifier,
        ) {
            Text("Add to Home Screen")
        }
    } else {
        Text(
            "Add the TrainTime widget from your home screen.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
            modifier = modifier,
        )
    }
}
