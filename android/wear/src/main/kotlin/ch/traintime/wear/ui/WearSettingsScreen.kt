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
import androidx.wear.compose.material.Text
import ch.traintime.shared.models.TransportMode
import ch.traintime.wear.viewmodels.WearViewModel

@Composable
fun WearSettingsScreen(viewModel: WearViewModel) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        item {
            Text(
                text = "Settings",
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                modifier = Modifier.padding(top = 24.dp, bottom = 8.dp)
            )
        }
        item {
            Text(
                text = "Default Mode",
                fontSize = 12.sp,
                color = Color.Gray,
                modifier = Modifier.padding(bottom = 4.dp)
            )
        }
        TransportMode.entries.forEach { mode ->
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            viewModel.updateDefaultMode(mode)
                            viewModel.showSettings = false
                        }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = mode.label,
                        fontSize = 14.sp,
                        color = Color.White
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    if (viewModel.defaultMode == mode) {
                        Text(text = "\u2713", fontSize = 14.sp, color = Color(0xFF55AAFF))
                    }
                }
            }
        }
    }
}
