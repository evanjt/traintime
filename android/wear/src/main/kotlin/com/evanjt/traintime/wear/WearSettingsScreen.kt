package com.evanjt.traintime.wear

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.ToggleChip
import androidx.wear.compose.material.ToggleChipDefaults
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.review.ReviewLauncher
import kotlinx.coroutines.launch

@Composable
fun WearSettingsScreen(vm: WearViewModel) {
    val listState = rememberScalingLazyListState()
    val scope = rememberCoroutineScope()
    val useRouted by vm.prefs.useRoutedDistance.collectAsState(initial = false)
    val activity = LocalContext.current as? Activity
    val config = LocalConfiguration.current
    val sidePad = (config.screenWidthDp * 0.06f).dp
    val vertPad = (config.screenHeightDp * 0.14f).dp

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            state = listState,
            contentPadding = PaddingValues(start = sidePad, end = sidePad, top = vertPad, bottom = vertPad),
            modifier = Modifier.fillMaxSize(),
        ) {
            item {
                Text(
                    "Default mode",
                    color = MaterialTheme.colors.onBackground,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 2.dp),
                )
            }
            items(TransportMode.entries.toList()) { mode ->
                ToggleChip(
                    checked = vm.defaultMode == mode,
                    onCheckedChange = { vm.updateDefaultMode(mode) },
                    label = { Text(mode.label) },
                    toggleControl = {
                        androidx.wear.compose.material.RadioButton(selected = vm.defaultMode == mode)
                    },
                    colors = ToggleChipDefaults.toggleChipColors(),
                )
            }
            item {
                ToggleChip(
                    checked = useRouted,
                    onCheckedChange = { value -> scope.launch { vm.prefs.setUseRoutedDistance(value) } },
                    label = { Text("Routed distance") },
                    toggleControl = {
                        androidx.wear.compose.material.Switch(checked = useRouted)
                    },
                    colors = ToggleChipDefaults.toggleChipColors(),
                )
            }
            item {
                Text(
                    "TrainTime ${BuildConfig.VERSION_NAME}",
                    color = MaterialTheme.colors.onSurfaceVariant,
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            item {
                Chip(
                    onClick = { activity?.let { ReviewLauncher.launch(it) } },
                    label = { Text("Rate TrainTime") },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                )
            }
        }
    }
}
