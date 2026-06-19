package com.evanjt.traintime.wear

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.domain.GeoUtils
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay

private val departureTimeFormat = DateTimeFormatter.ofPattern("HH:mm")

private fun formatDepartureTime(timestamp: Long): String =
    departureTimeFormat.format(Instant.ofEpochSecond(timestamp).atZone(ZoneId.systemDefault()))

@Composable
fun WearTrackingScreen(vm: WearViewModel) {
    val focused = vm.focusedTrain
    val palette = LocalWearPalette.current
    val secondary = MaterialTheme.colors.onSurfaceVariant
    val scrollState = rememberScrollState()

    // Keep the screen awake while tracking (the OngoingActivity covers wrist-down).
    val view = LocalView.current
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) {
        while (true) {
            nowSeconds = System.currentTimeMillis() / 1000
            delay(250)
        }
    }

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scrollState = scrollState) },
    ) {
        val config = androidx.compose.ui.platform.LocalConfiguration.current
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .padding(horizontal = 12.dp, vertical = (config.screenHeightDp * 0.16f).dp),
        ) {
            Text(vm.stationName, color = secondary, fontSize = 11.sp, maxLines = 1)

            val platChanged = focused?.platformChanged == true

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.padding(top = 6.dp),
            ) {
                if (focused != null && focused.lineNumber.isNotEmpty()) {
                    Text(
                        focused.lineNumber,
                        color = palette.platform,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                    )
                }
                Text(
                    focused?.destination ?: "?",
                    color = if (platChanged) palette.platformChangedOrange else MaterialTheme.colors.onBackground,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
                Text(
                    if (vm.isFocusedTrainFavourite) "★" else "☆",
                    color = if (vm.isFocusedTrainFavourite) palette.favouriteStar else secondary,
                    fontSize = 16.sp,
                    modifier = Modifier.clickable { vm.toggleFavourite() },
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.padding(top = 2.dp),
            ) {
                if (focused != null && focused.platform.isNotEmpty()) {
                    Text(
                        "Pl. ${focused.platform}",
                        color = if (platChanged) palette.platformChangedOrange else secondary,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                    )
                }
                if (focused != null) {
                    Text("·", color = secondary, fontSize = 10.sp)
                    Text(formatDepartureTime(focused.departureTimestamp), color = secondary, fontSize = 10.sp)
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(vertical = 6.dp),
            ) {
                Text(
                    focused?.countdownText(nowSeconds) ?: "—",
                    color = countdownColor(focused, nowSeconds, palette, secondary, MaterialTheme.colors.onBackground),
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                )
                if (focused != null && focused.delay > 0 && focused.minutesUntil(nowSeconds) >= -0.5) {
                    Text("+${focused.delay}", color = palette.delay, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            }

            TrackingBarWear(
                schedBuf = vm.trackingScheduledBuffer,
                effectBuf = vm.trackingEffectiveBuffer,
                hasGps = vm.gpsQuality != GpsQuality.UNAVAILABLE,
                modifier = Modifier.padding(horizontal = 16.dp),
            )

            val statusColor = when (vm.trackingStatus) {
                TrackingStatus.NO_GPS -> palette.barGray
                TrackingStatus.AHEAD -> palette.ahead
                TrackingStatus.ON_TIME -> palette.onTime
                TrackingStatus.BEHIND -> palette.behind
            }
            Text(
                vm.trackingStatusText,
                color = statusColor,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 8.dp),
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(top = 6.dp),
            ) {
                DirectionArrowWear(vm.directionToStation)
                Text(GeoUtils.formatWalkInfo(vm.lastWalkDist), color = secondary, fontSize = 12.sp)
            }

            vm.formation?.let { formation ->
                FormationDiagramWear(formation, Modifier.padding(top = 14.dp))
            }

            Text(
                "Back",
                color = palette.platform,
                fontSize = 14.sp,
                modifier = Modifier
                    .padding(top = 16.dp)
                    .clickable { vm.exitToStationView() },
            )
        }
    }
}

private fun countdownColor(
    focused: FocusedDeparture?,
    nowSeconds: Long,
    palette: WearPalette,
    secondary: Color,
    primary: Color,
): Color {
    if (focused == null) return primary
    val minutesUntil = focused.minutesUntil(nowSeconds)
    return when {
        minutesUntil < -0.5 -> secondary
        minutesUntil < 2.0 -> palette.minutesNow
        else -> palette.minutesSoon
    }
}
