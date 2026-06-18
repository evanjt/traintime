package com.evanjt.traintime.wear

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.data.model.TransportMode

@Composable
fun LinePill(line: String, mode: TransportMode, isGone: Boolean) {
    if (line.isEmpty()) return
    val palette = LocalWearPalette.current
    Text(
        line,
        color = if (isGone) MaterialTheme.colors.onSurfaceVariant else Color.White,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(5.dp))
            .background(if (isGone) MaterialTheme.colors.surface else palette.linePill(line, mode))
            .padding(horizontal = 5.dp, vertical = 1.dp),
    )
}

@Composable
fun GpsDot(quality: GpsQuality, modifier: Modifier = Modifier) {
    Box(modifier.size(9.dp).clip(CircleShape).background(quality.tint))
}

@Composable
fun GoldSeparator(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .height(2.dp)
            .background(LocalWearPalette.current.favouriteSeparator),
    )
}

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
            .clip(RoundedCornerShape(10.dp))
            .background(if (isFavourite) palette.favouriteBackground else Color.Transparent)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 8.dp, vertical = 7.dp),
    ) {
        Text(
            departure.minutesText,
            color = minutesColor,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            textAlign = TextAlign.End,
            modifier = Modifier.width(34.dp),
        )
        Spacer(Modifier.width(6.dp))
        LinePill(departure.lineNumber, mode, departure.isGone)
        Spacer(Modifier.width(6.dp))
        Column(Modifier.weight(1f)) {
            Text(
                departure.destination,
                color = if (departure.isGone) secondary else MaterialTheme.colors.onSurface,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (departure.platform.isNotEmpty() || (departure.delay > 0 && !departure.isGone)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (departure.platform.isNotEmpty()) {
                        Text(
                            "Pl. ${departure.platform}",
                            color = if (departure.platformChanged) palette.platformChangedOrange else secondary,
                            fontSize = 11.sp,
                        )
                    }
                    if (departure.delay > 0 && !departure.isGone) {
                        if (departure.platform.isNotEmpty()) Spacer(Modifier.width(6.dp))
                        Text("+${departure.delay}", color = palette.delay, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
        if (isFavourite) {
            Text("★", color = palette.favouriteStar, fontSize = 14.sp, modifier = Modifier.padding(start = 2.dp))
        }
    }
}

// Direction-to-station arrow drawn as a chevron so we avoid an icons dependency.
@Composable
fun DirectionArrowWear(degrees: Double?, modifier: Modifier = Modifier) {
    if (degrees == null) return
    Canvas(modifier.size(16.dp).rotate(degrees.toFloat())) {
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

// Port of TrackingBarView.swift / the phone TrackingBar: ±3 min of buffer maps
// to half the bar. Dark green = guaranteed, light green = saved by the delay,
// amber = recoverable, dark red = irrecoverable.
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
            .height(12.dp)
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
                drawRect(
                    palette.darkGreen,
                    topLeft = Offset(midX, 0f),
                    size = Size((schedPos - midX).coerceAtLeast(0f), size.height),
                )
                if (effectPos > schedPos) {
                    drawRect(
                        palette.lightGreen,
                        topLeft = Offset(schedPos, 0f),
                        size = Size(effectPos - schedPos, size.height),
                    )
                }
            } else if (schedBuf < 0 && effectBuf < 0) {
                drawRect(
                    palette.darkRed,
                    topLeft = Offset(effectPos, 0f),
                    size = Size((midX - effectPos).coerceAtLeast(0f), size.height),
                )
                if (schedPos < effectPos) {
                    drawRect(
                        palette.amber,
                        topLeft = Offset(schedPos, 0f),
                        size = Size(effectPos - schedPos, size.height),
                    )
                }
            } else if (schedBuf < 0 && effectBuf >= 0) {
                drawRect(
                    palette.amber,
                    topLeft = Offset(schedPos, 0f),
                    size = Size((midX - schedPos).coerceAtLeast(0f), size.height),
                )
                drawRect(
                    palette.lightGreen,
                    topLeft = Offset(midX, 0f),
                    size = Size((effectPos - midX).coerceAtLeast(0f), size.height),
                )
            }
        }

        drawRect(
            palette.barGray.copy(alpha = 0.8f),
            topLeft = Offset(midX - 1, 0f),
            size = Size(2f, size.height),
        )
    }
}
