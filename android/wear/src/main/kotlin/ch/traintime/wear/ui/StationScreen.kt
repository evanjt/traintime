package ch.traintime.wear.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import ch.traintime.shared.AppColors
import ch.traintime.shared.models.Departure
import ch.traintime.shared.models.GPSQuality
import ch.traintime.shared.models.TransportMode
import ch.traintime.wear.viewmodels.WearViewModel

@Composable
fun StationScreen(viewModel: WearViewModel) {
    val listState = rememberScalingLazyListState()

    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Mode picker + GPS
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 24.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                WearModePickerBar(
                    availableModes = viewModel.availableModes,
                    currentMode = viewModel.currentMode,
                    onSelect = { viewModel.selectMode(it) }
                )
                Spacer(modifier = Modifier.width(8.dp))
                WearGpsIndicator(quality = viewModel.gpsQuality)
            }
        }

        // Walk info
        item {
            Text(
                text = viewModel.walkInfo,
                fontSize = 11.sp,
                color = Color(0xFFAAAAAA)
            )
        }

        // Station name
        item {
            Text(
                text = viewModel.stationName.uppercase(),
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .clickable { viewModel.showStationPicker = true }
                    .padding(vertical = 4.dp)
            )
        }

        // Departures or status
        if (viewModel.departures.isEmpty()) {
            item {
                if (viewModel.stations.isEmpty()) {
                    Text(
                        text = viewModel.status,
                        fontSize = 12.sp,
                        color = Color.Gray,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 16.dp)
                    )
                } else {
                    Text(
                        text = if (viewModel.requestInFlight) "Loading..." else viewModel.status,
                        fontSize = 12.sp,
                        color = Color.Gray,
                        modifier = Modifier.padding(top = 16.dp)
                    )
                }
            }
        } else {
            itemsIndexed(viewModel.departures) { index, departure ->
                WearDepartureRow(
                    departure = departure,
                    onTap = { viewModel.selectDeparture(index) }
                )
            }
        }
    }

    if (viewModel.showStationPicker) {
        WearStationPicker(viewModel = viewModel)
    }
}

@Composable
fun WearDepartureRow(departure: Departure, onTap: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !departure.isGone, onClick = onTap)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Minutes
        Text(
            text = departure.minutesText,
            fontSize = if (departure.minutesUntil <= 0) 12.sp else 16.sp,
            fontWeight = FontWeight.Bold,
            color = when {
                departure.isGone -> Color.Gray
                departure.minutesUntil <= 2 -> Color(AppColors.MINUTES_NOW)
                else -> Color(AppColors.MINUTES_SOON)
            },
            modifier = Modifier.width(34.dp)
        )

        // Delay
        Text(
            text = if (departure.delay > 0 && !departure.isGone) "+${departure.delay}" else "",
            fontSize = 9.sp,
            fontWeight = FontWeight.Medium,
            color = Color(AppColors.DELAY),
            modifier = Modifier.width(14.dp)
        )

        // Line or platform
        Box(modifier = Modifier.width(28.dp)) {
            if (departure.lineNumber.isNotEmpty()) {
                Text(
                    text = departure.lineNumber,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (departure.isGone) Color.Gray else Color(AppColors.PLATFORM)
                )
            } else if (departure.platform.isNotEmpty()) {
                Text(
                    text = "P${departure.platform}",
                    fontSize = 10.sp,
                    color = if (departure.isGone) Color.Gray else Color(AppColors.PLATFORM)
                )
            }
        }

        // Destination
        Text(
            text = departure.destination,
            fontSize = 13.sp,
            color = if (departure.isGone) Color.Gray else Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
fun WearModePickerBar(
    availableModes: List<TransportMode>,
    currentMode: TransportMode,
    onSelect: (TransportMode) -> Unit
) {
    val icons = mapOf(
        TransportMode.TRAIN to "\uD83D\uDE86",
        TransportMode.BUS to "\uD83D\uDE8C",
        TransportMode.TRAM to "\uD83D\uDE8A",
        TransportMode.SPECIAL to "\uD83D\uDEA1"
    )

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TransportMode.entries.forEach { mode ->
            val isAvailable = mode in availableModes
            val isCurrent = mode == currentMode
            Text(
                text = icons[mode] ?: "",
                fontSize = 16.sp,
                color = when {
                    !isAvailable -> Color.White.copy(alpha = 0.15f)
                    isCurrent -> Color.White
                    else -> Color.Gray
                },
                modifier = Modifier.clickable(enabled = isAvailable) { onSelect(mode) }
            )
        }
    }
}

@Composable
fun WearGpsIndicator(quality: GPSQuality) {
    Box(
        modifier = Modifier
            .size(8.dp)
            .padding(1.dp)
    ) {
        androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
            drawCircle(Color(quality.colorInt))
        }
    }
}
