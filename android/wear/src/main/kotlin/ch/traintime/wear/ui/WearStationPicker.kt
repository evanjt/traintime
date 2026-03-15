package ch.traintime.wear.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.material.Text
import ch.traintime.shared.AppColors
import ch.traintime.shared.geo.GeoUtils
import ch.traintime.wear.viewmodels.WearViewModel

@Composable
fun WearStationPicker(viewModel: WearViewModel) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        item {
            Text(
                text = "Select Station",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                modifier = Modifier.padding(top = 24.dp, bottom = 8.dp)
            )
        }

        itemsIndexed(viewModel.stations) { index, station ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.selectStation(index) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = station.name ?: "Unknown",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (index == viewModel.stationIndex) Color(AppColors.SELECTION_ACCENT) else Color.White
                    )
                    Text(
                        text = GeoUtils.formatWalkInfo(station.dist ?: 0.0),
                        fontSize = 10.sp,
                        color = Color.Gray
                    )
                }
                if (index == viewModel.stationIndex) {
                    Text(text = "\u2713", fontSize = 14.sp, color = Color(AppColors.SELECTION_ACCENT))
                }
            }
        }
    }
}
