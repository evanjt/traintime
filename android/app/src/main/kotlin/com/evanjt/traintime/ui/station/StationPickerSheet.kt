package com.evanjt.traintime.ui.station

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.ui.MainViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StationPickerSheet(viewModel: MainViewModel) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    ModalBottomSheet(
        onDismissRequest = { viewModel.showStationPicker = false },
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(Modifier.padding(bottom = 24.dp)) {
            Text(
                "Stations",
                color = MaterialTheme.colorScheme.onSurface,
                fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            viewModel.stations.forEachIndexed { index, station ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.selectStation(index) }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(station.name ?: "?", color = MaterialTheme.colorScheme.onSurface)
                        Text(
                            GeoUtils.formatWalkInfo(station.dist ?: 0.0),
                            color = secondary,
                            fontSize = 12.sp,
                        )
                    }
                    Spacer(Modifier.padding(4.dp))
                    if (index == viewModel.stationIndex) {
                        Icon(Icons.Filled.Check, contentDescription = "Selected", tint = palette.platform)
                    }
                }
            }
        }
    }
}
