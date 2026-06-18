package com.evanjt.traintime.wear

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.evanjt.traintime.core.sync.WearSync

class MainActivity : ComponentActivity() {
    private val viewModel: WearViewModel by viewModels()

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        val granted = result[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            result[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        viewModel.onPermissionResult(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleTrackIntent(intent)
        setContent {
            TrainTimeWearTheme { WearApp(viewModel) }
        }
        if (!viewModel.location.hasPermission) {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTrackIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        viewModel.onAppear()
    }

    override fun onPause() {
        super.onPause()
        viewModel.onDisappear()
    }

    private fun handleTrackIntent(intent: Intent?) {
        val raw = intent?.getStringExtra(EXTRA_TRACK) ?: return
        WearSync.decodeTrackString(raw)?.let { viewModel.handleTrackCommand(it) }
    }

    companion object {
        const val EXTRA_TRACK = "com.evanjt.traintime.wear.EXTRA_TRACK"
    }
}

private enum class MainScreen { LIST, PICKER, SETTINGS }

@Composable
fun WearApp(vm: WearViewModel) {
    when (vm.appState) {
        2 -> {
            BackHandler { vm.exitToStationView() }
            WearTrackingScreen(vm)
        }
        3 -> InactiveScreen(vm)
        else -> {
            var screen by remember { mutableStateOf(MainScreen.LIST) }
            BackHandler(enabled = screen != MainScreen.LIST) { screen = MainScreen.LIST }
            when (screen) {
                MainScreen.LIST -> WearStationListScreen(
                    vm = vm,
                    onOpenPicker = { screen = MainScreen.PICKER },
                    onOpenSettings = { screen = MainScreen.SETTINGS },
                )
                MainScreen.PICKER -> WearStationPickerScreen(vm) { screen = MainScreen.LIST }
                MainScreen.SETTINGS -> WearSettingsScreen(vm)
            }
        }
    }
}

@Composable
private fun InactiveScreen(vm: WearViewModel) {
    Box(
        modifier = Modifier.fillMaxSize().clickable { vm.resumeFromInactive() },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "Tap to resume",
            color = MaterialTheme.colors.onSurfaceVariant,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(16.dp),
        )
    }
}
