package ch.traintime.phone.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ch.traintime.phone.ui.components.*
import ch.traintime.phone.viewmodels.PhoneViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StationScreen(viewModel: PhoneViewModel) {
    var showSettings by remember { mutableStateOf(false) }
    Column(modifier = Modifier.fillMaxSize()) {
        // Header: Mode picker + GPS
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ModePickerBar(
                availableModes = viewModel.availableModes,
                currentMode = viewModel.currentMode,
                onSelect = { viewModel.selectMode(it) }
            )
            Spacer(modifier = Modifier.weight(1f))
            GpsIndicator(quality = viewModel.gpsQuality)
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(
                onClick = { showSettings = true },
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    Icons.Default.Settings,
                    contentDescription = "Settings",
                    tint = Color.Gray,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        // Walk info
        Text(
            text = viewModel.walkInfo,
            fontSize = 14.sp,
            color = Color(0xFFAAAAAA),
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .padding(top = 4.dp)
        )

        // Station name button
        Row(
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .clickable { viewModel.showStationPicker = true }
                .padding(top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = viewModel.stationName.uppercase(),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (viewModel.stations.size > 1) {
                Spacer(modifier = Modifier.width(6.dp))
                Text(text = "\u25BE", fontSize = 12.sp, color = Color.Gray)
            }
        }

        // Divider
        HorizontalDivider(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = Color(0xFF444444)
        )

        // Departure list or status
        if (viewModel.departures.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                if (viewModel.stations.isEmpty()) {
                    Text(
                        text = viewModel.status,
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                } else {
                    CircularProgressIndicator(
                        color = Color.Gray,
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp
                    )
                }
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                itemsIndexed(viewModel.departures) { index, departure ->
                    DepartureRow(
                        departure = departure,
                        onTap = { viewModel.selectDeparture(index) }
                    )
                }
            }
        }
    }

    // Station picker bottom sheet
    if (viewModel.showStationPicker) {
        StationPickerSheet(viewModel = viewModel)
    }

    if (showSettings) {
        SettingsDialog(viewModel = viewModel, onDismiss = { showSettings = false })
    }
}
