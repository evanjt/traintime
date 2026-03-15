package ch.traintime.phone.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ch.traintime.shared.AppColors
import ch.traintime.shared.geo.GeoUtils
import ch.traintime.phone.viewmodels.PhoneViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StationPickerSheet(viewModel: PhoneViewModel) {
    ModalBottomSheet(
        onDismissRequest = { viewModel.showStationPicker = false },
        containerColor = Color(0xFF1C1C1E)
    ) {
        Text(
            text = "Select Station",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )

        LazyColumn(modifier = Modifier.padding(bottom = 32.dp)) {
            itemsIndexed(viewModel.stations) { index, station ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.selectStation(index) }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = station.name ?: "Unknown",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (index == viewModel.stationIndex) Color(AppColors.SELECTION_ACCENT) else Color.White
                        )
                        val dist = station.dist ?: 0.0
                        Text(
                            text = GeoUtils.formatWalkInfo(dist),
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }
                    if (index == viewModel.stationIndex) {
                        Text(text = "\u2713", fontSize = 16.sp, color = Color(AppColors.SELECTION_ACCENT))
                    }
                }
            }
        }
    }
}
