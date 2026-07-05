package com.evanjt.traintime.wear

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.SwipeToDismissBox
import androidx.wear.compose.material.Text
import com.evanjt.traintime.core.sync.WearSync

class MainActivity : ComponentActivity() {
    private val viewModel: WearViewModel by viewModels()

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        // A notifications-only ask must not read as a location denial.
        if (Manifest.permission.ACCESS_FINE_LOCATION in result ||
            Manifest.permission.ACCESS_COARSE_LOCATION in result
        ) {
            val granted = result[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                result[Manifest.permission.ACCESS_COARSE_LOCATION] == true
            viewModel.onPermissionResult(granted)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleTrackIntent(intent)
        setContent {
            TrainTimeWearTheme { WearApp(viewModel) }
        }
        if (!viewModel.location.hasPermission) {
            permissionLauncher.launch(locationPermissions())
        } else {
            maybeRequestNotifications()
        }
    }

    private fun locationPermissions(): Array<String> = buildList {
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        // API 33+: without this the OngoingActivity notification (wrist-down
        // tracking survival) never shows. Piggybacks on the location ask.
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }.toTypedArray()

    private fun maybeRequestNotifications() {
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            permissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
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
    WearReviewPrompt(vm)
    when (vm.appState) {
        2 -> {
            BackHandler { vm.exitToStationView() }
            DismissableScreen(onDismiss = { vm.exitToStationView() }) {
                WearTrackingScreen(vm)
            }
        }
        3 -> InactiveScreen(vm)
        else -> {
            var screen by remember { mutableStateOf(MainScreen.LIST) }
            BackHandler(enabled = screen != MainScreen.LIST) { screen = MainScreen.LIST }
            // Reading settings or the picker must not trip the inactivity
            // timeout; leaving them restarts the idle clock.
            LaunchedEffect(screen) {
                vm.subScreenOpen = screen != MainScreen.LIST
                if (screen == MainScreen.LIST) vm.noteInteraction()
            }
            when (screen) {
                MainScreen.LIST -> WearStationListScreen(
                    vm = vm,
                    onOpenPicker = { screen = MainScreen.PICKER },
                    onOpenSettings = { screen = MainScreen.SETTINGS },
                )
                MainScreen.PICKER -> DismissableScreen(onDismiss = { screen = MainScreen.LIST }) {
                    WearStationPickerScreen(vm) { screen = MainScreen.LIST }
                }
                MainScreen.SETTINGS -> DismissableScreen(onDismiss = { screen = MainScreen.LIST }) {
                    WearSettingsScreen(vm, onNavigateHome = { screen = MainScreen.LIST })
                }
            }
        }
    }
}

// Wear-native edge swipe-to-dismiss for sub-screens, alongside the system back
// path the BackHandlers keep working.
@Composable
private fun DismissableScreen(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    SwipeToDismissBox(onDismissed = onDismiss) { isBackground ->
        if (isBackground) {
            Box(Modifier.fillMaxSize())
        } else {
            content()
        }
    }
}

@Composable
private fun InactiveScreen(vm: WearViewModel) {
    // Mirrors the Apple watch's inactive screen: a titled pause state with an
    // explicit Resume control (the whole screen stays tappable too).
    Box(
        modifier = Modifier.fillMaxSize().clickable { vm.resumeFromInactive() },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                "Inactive",
                color = MaterialTheme.colors.onSurfaceVariant,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
            )
            Chip(
                onClick = { vm.resumeFromInactive() },
                label = { Text("Resume") },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.padding(top = 10.dp),
            )
        }
    }
}
