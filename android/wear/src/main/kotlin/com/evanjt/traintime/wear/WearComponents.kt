package com.evanjt.traintime.wear

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsBoat
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Train
import androidx.compose.material.icons.filled.Tram
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.data.model.TransportMode

private val TransportMode.icon: ImageVector
    get() = when (this) {
        TransportMode.TRAIN -> Icons.Filled.Train
        TransportMode.BUS -> Icons.Filled.DirectionsBus
        TransportMode.TRAM -> Icons.Filled.Tram
        TransportMode.SPECIAL -> Icons.Filled.DirectionsBoat
    }

// Compact inline mode selector, mirroring the Apple watch ModeIndicatorView:
// small icon buttons, current one highlighted, unavailable modes dimmed.
@Composable
fun ModeIconRow(vm: WearViewModel) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        TransportMode.entries.forEach { mode ->
            val available = mode in vm.availableModes
            val current = mode == vm.currentMode && available
            val tint = when {
                current -> MaterialTheme.colors.onBackground
                available -> MaterialTheme.colors.onSurfaceVariant
                else -> MaterialTheme.colors.onBackground.copy(alpha = 0.18f)
            }
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(if (current) MaterialTheme.colors.onBackground.copy(alpha = 0.15f) else Color.Transparent)
                    .clickable(enabled = available) { vm.selectMode(mode) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(mode.icon, contentDescription = mode.label, tint = tint, modifier = Modifier.size(15.dp))
            }
        }
    }
}

@Composable
fun GpsIcon(quality: GpsQuality, modifier: Modifier = Modifier) {
    Icon(Icons.Filled.LocationOn, contentDescription = "GPS", tint = quality.tint, modifier = modifier.size(15.dp))
}

@Composable
fun GoldSeparator(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .height(2.dp)
            .background(LocalWearPalette.current.favouriteSeparator),
    )
}

// Mirrors the Apple watch DepartureRowView: minutes | small delay | plain
// coloured line number (no pill) | destination. Favourites are shown by the gold
// background only — no star glyph, no trailing chevron.
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WearDepartureRow(
    departure: Departure,
    isFavourite: Boolean,
    mode: TransportMode,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val palette = LocalWearPalette.current
    val secondary = MaterialTheme.colors.onSurfaceVariant
    val minutesColor = when {
        departure.isGone -> secondary
        departure.minutesUntil <= 2 -> palette.minutesNow
        else -> palette.minutesSoon
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(if (isFavourite) palette.favouriteBackground else Color.Transparent)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 4.dp, vertical = 4.dp),
    ) {
        Text(
            departure.minutesText,
            color = minutesColor,
            fontSize = if (departure.isGone) 11.sp else 14.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            textAlign = TextAlign.End,
            modifier = Modifier.width(34.dp),
        )
        Text(
            if (departure.delay > 0 && !departure.isGone) "+${departure.delay}" else "",
            color = palette.delay,
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            modifier = Modifier.width(15.dp).padding(start = 1.dp),
        )
        Text(
            departure.lineNumber,
            color = if (departure.isGone) secondary else palette.platform,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            modifier = Modifier.width(32.dp),
        )
        Spacer(Modifier.width(3.dp))
        Text(
            departure.destination,
            color = if (departure.isGone) secondary else MaterialTheme.colors.onSurface,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

// Direction-to-station arrow drawn as a chevron so we avoid an extra dependency.
@Composable
fun DirectionArrowWear(degrees: Double?, modifier: Modifier = Modifier) {
    if (degrees == null) return
    Canvas(modifier.size(14.dp).rotate(degrees.toFloat())) {
        val w = size.width
        val h = size.height
        val path = Path().apply {
            moveTo(w / 2f, 0f)
            lineTo(w, h)
            lineTo(w / 2f, h * 0.7f)
            lineTo(0f, h)
            close()
        }
        drawPath(path, Color.White)
    }
}

// Port of TrackingBarView: ±3 min of buffer maps to half the bar. Dark green =
// guaranteed, light green = saved by the delay, amber = recoverable, dark red =
// irrecoverable.
@Composable
fun TrackingBarWear(
    schedBuf: Double,
    effectBuf: Double,
    hasGps: Boolean,
    modifier: Modifier = Modifier,
) {
    val palette = LocalWearPalette.current
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(10.dp)
            .clip(RoundedCornerShape(3.dp)),
    ) {
        val width = size.width
        val midX = width / 2
        val scale = Thresholds.BAR_SCALE

        fun position(buffer: Double): Float {
            val clamped = buffer.coerceIn(-scale, scale)
            return (midX + (clamped / scale) * midX).toFloat()
        }

        drawRect(palette.trackingBarBackground)

        if (!hasGps) {
            drawRect(palette.barGray)
        } else {
            val schedPos = position(schedBuf)
            val effectPos = position(effectBuf)

            if (schedBuf >= 0 && effectBuf >= 0) {
                drawRect(palette.darkGreen, topLeft = Offset(midX, 0f), size = Size((schedPos - midX).coerceAtLeast(0f), size.height))
                if (effectPos > schedPos) {
                    drawRect(palette.lightGreen, topLeft = Offset(schedPos, 0f), size = Size(effectPos - schedPos, size.height))
                }
            } else if (schedBuf < 0 && effectBuf < 0) {
                drawRect(palette.darkRed, topLeft = Offset(effectPos, 0f), size = Size((midX - effectPos).coerceAtLeast(0f), size.height))
                if (schedPos < effectPos) {
                    drawRect(palette.amber, topLeft = Offset(schedPos, 0f), size = Size(effectPos - schedPos, size.height))
                }
            } else if (schedBuf < 0 && effectBuf >= 0) {
                drawRect(palette.amber, topLeft = Offset(schedPos, 0f), size = Size((midX - schedPos).coerceAtLeast(0f), size.height))
                drawRect(palette.lightGreen, topLeft = Offset(midX, 0f), size = Size((effectPos - midX).coerceAtLeast(0f), size.height))
            }
        }

        drawRect(palette.barGray.copy(alpha = 0.8f), topLeft = Offset(midX - 1, 0f), size = Size(2f, size.height))
    }
}
