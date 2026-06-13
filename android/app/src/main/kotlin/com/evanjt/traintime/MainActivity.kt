package com.evanjt.traintime

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.settings.SettingsSheet
import com.evanjt.traintime.ui.station.InactiveScreen
import com.evanjt.traintime.ui.station.StationPickerSheet
import com.evanjt.traintime.ui.station.StationScreen
import com.evanjt.traintime.ui.theme.TrainTimeTheme
import com.evanjt.traintime.ui.tracking.TrackingScreen

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels()

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
            viewModel.onPermissionResult(grants.values.any { it })
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            TrainTimeTheme {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    RootView(viewModel)
                }
            }
        }

        if (!viewModel.location.hasPermission) {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }

        intent?.data?.let { viewModel.handleDeepLink(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let { viewModel.handleDeepLink(it) }
    }
}

@Composable
private fun RootView(viewModel: MainViewModel) {
    // scenePhase equivalent: foreground lifecycle drives timers and GPS.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> viewModel.onAppear()
                Lifecycle.Event.ON_STOP -> viewModel.onDisappear()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    var showSettings by remember { mutableStateOf(false) }

    // targetSdk 35 forces edge-to-edge, so inset the content below the status
    // bar and above the nav bar (the Surface background still fills behind them).
    Box(Modifier.fillMaxSize().systemBarsPadding()) {
        when (viewModel.appState) {
            2 -> TrackingScreen(viewModel)
            3 -> InactiveScreen(onResume = { viewModel.resumeFromInactive() })
            else -> StationScreen(viewModel, onOpenSettings = { showSettings = true })
        }
    }

    if (viewModel.showStationPicker) {
        StationPickerSheet(viewModel)
    }
    if (showSettings) {
        SettingsSheet(viewModel, onDismiss = { showSettings = false })
    }
}
