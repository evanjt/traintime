package ch.traintime.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import ch.traintime.shared.AppColors
import ch.traintime.shared.Thresholds
import ch.traintime.shared.geo.GeoUtils
import ch.traintime.shared.models.GPSQuality
import ch.traintime.wear.viewmodels.WearViewModel

@Composable
fun FocusedTrackingScreen(viewModel: WearViewModel, onBack: () -> Unit) {
    val focused = viewModel.focusedTrain
    val listState = rememberScalingLazyListState()

    // Handle back via system gesture — Wear OS uses swipe-right natively

    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Station name
        item {
            Text(
                text = viewModel.stationName,
                fontSize = 11.sp,
                color = Color(0xFFAAAAAA),
                modifier = Modifier.padding(top = 24.dp)
            )
        }

        // Destination + platform
        item {
            val platChanged = focused?.platformChanged == true
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = focused?.destination ?: "?",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (platChanged) Color(AppColors.PLATFORM_CHANGED_ORANGE) else Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                val plat = focused?.platform
                if (!plat.isNullOrEmpty()) {
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "P$plat",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (platChanged) Color.White else Color(AppColors.PLATFORM)
                    )
                }
            }
        }

        // Countdown
        item {
            val minutesUntil = focused?.minutesUntil
            val color = when {
                minutesUntil == null -> Color.White
                minutesUntil < -0.5 -> Color.Gray
                minutesUntil < 2.0 -> Color(AppColors.MINUTES_NOW)
                else -> Color(AppColors.MINUTES_SOON)
            }
            Text(
                text = focused?.countdownText ?: "\u2014",
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold,
                color = color
            )
        }

        // Delay badge
        if (focused != null && focused.delay > 0 && focused.minutesUntil >= -0.5) {
            item {
                Text(
                    text = "+${focused.delay}",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(AppColors.DELAY)
                )
            }
        }

        // Tracking bar
        item {
            WearTrackingBar(
                schedBuf = viewModel.trackingScheduledBuffer,
                effectBuf = viewModel.trackingEffectiveBuffer,
                hasGPS = viewModel.gpsQuality != GPSQuality.UNAVAILABLE,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(12.dp)
                    .padding(horizontal = 16.dp)
            )
        }

        // Status
        item {
            Text(
                text = viewModel.trackingStatusText,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color(viewModel.trackingStatusColorInt)
            )
        }

        // Walk info + direction
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                WearDirectionArrow(degrees = viewModel.directionToStation)
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = GeoUtils.formatWalkInfo(viewModel.lastWalkDist),
                    fontSize = 11.sp,
                    color = Color(0xFFAAAAAA)
                )
            }
        }
    }
}

@Composable
fun WearTrackingBar(
    schedBuf: Double,
    effectBuf: Double,
    hasGPS: Boolean,
    modifier: Modifier = Modifier
) {
    val scale = Thresholds.BAR_SCALE

    Canvas(modifier = modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height
        val midX = width / 2

        drawRect(Color.Black, size = size)

        if (!hasGPS) {
            drawRect(Color(AppColors.BAR_GRAY), size = size)
        } else {
            fun bufToPos(buf: Double): Float {
                val clamped = buf.coerceIn(-scale, scale)
                return midX + ((clamped / scale) * midX).toFloat()
            }

            val schedPos = bufToPos(schedBuf)
            val effectPos = bufToPos(effectBuf)

            if (schedBuf >= 0 && effectBuf >= 0) {
                drawRect(Color(AppColors.DARK_GREEN), Offset(midX, 0f), Size(maxOf(0f, schedPos - midX), height))
                if (effectPos > schedPos) {
                    drawRect(Color(AppColors.LIGHT_GREEN), Offset(schedPos, 0f), Size(effectPos - schedPos, height))
                }
            } else if (schedBuf < 0 && effectBuf < 0) {
                drawRect(Color(AppColors.DARK_RED), Offset(effectPos, 0f), Size(maxOf(0f, midX - effectPos), height))
                if (schedPos < effectPos) {
                    drawRect(Color(AppColors.AMBER), Offset(schedPos, 0f), Size(effectPos - schedPos, height))
                }
            } else if (schedBuf < 0 && effectBuf >= 0) {
                drawRect(Color(AppColors.AMBER), Offset(schedPos, 0f), Size(maxOf(0f, midX - schedPos), height))
                drawRect(Color(AppColors.LIGHT_GREEN), Offset(midX, 0f), Size(maxOf(0f, effectPos - midX), height))
            }
        }

        drawRect(Color(AppColors.BAR_GRAY).copy(alpha = 0.8f), Offset(midX - 1, 0f), Size(2f, height))
    }
}

@Composable
fun WearDirectionArrow(degrees: Double?, modifier: Modifier = Modifier) {
    if (degrees == null) return

    Canvas(modifier = modifier.size(16.dp)) {
        rotate(degrees.toFloat()) {
            val path = Path().apply {
                moveTo(size.width / 2, 0f)
                lineTo(size.width, size.height)
                lineTo(size.width / 2, size.height * 0.7f)
                lineTo(0f, size.height)
                close()
            }
            drawPath(path, Color.White)
        }
    }
}
