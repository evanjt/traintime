package ch.traintime.phone.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ch.traintime.shared.AppColors
import ch.traintime.shared.geo.GeoUtils
import ch.traintime.shared.models.GPSQuality
import ch.traintime.phone.ui.components.DirectionArrow
import ch.traintime.phone.ui.components.TrackingBar
import ch.traintime.phone.viewmodels.PhoneViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusedTrackingScreen(viewModel: PhoneViewModel, onBack: () -> Unit) {
    val focused = viewModel.focusedTrain

    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Black)
            )
        },
        containerColor = Color.Black
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Station name
            Text(
                text = viewModel.stationName,
                fontSize = 14.sp,
                color = Color(0xFFAAAAAA)
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Destination + platform
            val platChanged = focused?.platformChanged == true
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                Text(
                    text = focused?.let { if (it.lineNumber.isNotEmpty()) "${it.lineNumber} ${it.destination}" else it.destination } ?: "?",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (platChanged) Color(AppColors.PLATFORM_CHANGED_ORANGE) else Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                val plat = focused?.platform
                if (!plat.isNullOrEmpty()) {
                    Spacer(modifier = Modifier.width(6.dp))
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = if (platChanged) Color(AppColors.PLATFORM_CHANGED_ORANGE) else Color.Transparent
                    ) {
                        Text(
                            text = "P$plat",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (platChanged) Color.White else Color(AppColors.PLATFORM),
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp)
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Countdown
            Text(
                text = focused?.countdownText ?: "\u2014",
                fontSize = 48.sp,
                fontWeight = FontWeight.Bold,
                color = countdownColor(focused?.minutesUntil)
            )

            // Delay badge
            if (focused != null && focused.delay > 0 && focused.minutesUntil >= -0.5) {
                Spacer(modifier = Modifier.height(8.dp))
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = Color(AppColors.DELAY)
                ) {
                    Text(
                        text = "+${focused.delay}",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Tracking bar
            TrackingBar(
                schedBuf = viewModel.trackingScheduledBuffer,
                effectBuf = viewModel.trackingEffectiveBuffer,
                hasGPS = viewModel.gpsQuality != GPSQuality.UNAVAILABLE,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(16.dp)
                    .padding(horizontal = 24.dp)
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Status
            Text(
                text = viewModel.trackingStatusText,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color(viewModel.trackingStatusColorInt)
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Walk info + direction
            Row(verticalAlignment = Alignment.CenterVertically) {
                DirectionArrow(degrees = viewModel.directionToStation)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = GeoUtils.formatWalkInfo(viewModel.lastWalkDist, viewModel.lastWalkTime),
                    fontSize = 14.sp,
                    color = Color(0xFFAAAAAA)
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Send to Watch
            val watches = viewModel.connectedWatches
            val sendStatus = viewModel.watchSendStatus

            LaunchedEffect(Unit) {
                viewModel.refreshConnectedWatches()
            }

            if (watches.size <= 1) {
                // Single watch or none — one button
                OutlinedButton(
                    onClick = { viewModel.sendToWatch() },
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    border = ButtonDefaults.outlinedButtonBorder(enabled = true).copy(
                        brush = androidx.compose.ui.graphics.SolidColor(Color(0xFF444444))
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "\u231A  Send to Watch",
                        fontSize = 14.sp
                    )
                }
            } else {
                // Multiple watches — one button per watch
                for (watch in watches) {
                    OutlinedButton(
                        onClick = { viewModel.sendToWatch(watch) },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                        border = ButtonDefaults.outlinedButtonBorder(enabled = true).copy(
                            brush = androidx.compose.ui.graphics.SolidColor(Color(0xFF444444))
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = "\u231A  ${watch.name}",
                            fontSize = 14.sp
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                }
            }

            if (sendStatus != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = sendStatus,
                    fontSize = 12.sp,
                    color = Color(0xFFAAAAAA)
                )
            }
        }
    }
}

private fun countdownColor(minutesUntil: Double?): Color {
    if (minutesUntil == null) return Color.White
    if (minutesUntil < -0.5) return Color.Gray
    if (minutesUntil < 2.0) return Color(AppColors.MINUTES_NOW)
    return Color(AppColors.MINUTES_SOON)
}
