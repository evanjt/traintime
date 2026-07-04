package com.evanjt.traintime

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.evanjt.traintime.review.ReviewGate
import com.evanjt.traintime.review.ReviewLauncher
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.onboarding.OnboardingTour
import com.evanjt.traintime.ui.settings.AttributionSheet
import com.evanjt.traintime.ui.settings.SettingsSheet
import com.evanjt.traintime.ui.station.InactiveScreen
import com.evanjt.traintime.ui.station.StationPickerSheet
import com.evanjt.traintime.ui.station.StationScreen
import com.evanjt.traintime.ui.theme.TrainTimeTheme
import com.evanjt.traintime.ui.tracking.TrackingScreen
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels()

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
            viewModel.onPermissionResult(grants.values.any { it })
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            val appearanceMode by viewModel.prefs.appearanceMode.collectAsState(initial = "system")
            // values-night/themes.xml keys the status-bar icon colour on the system
            // night mode, so a manual override needs the bars set to match.
            val dark = when (appearanceMode) {
                "light" -> false
                "dark" -> true
                else -> isSystemInDarkTheme()
            }
            SideEffect {
                WindowCompat.getInsetsController(window, window.decorView)
                    .isAppearanceLightStatusBars = !dark
            }
            TrainTimeTheme(appearanceMode = appearanceMode) {
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

    // Auto-prompt for a review once the user has tracked a few departures, and
    // only once per version. Increment on each fresh entry into tracking (state
    // 2), guarding the transition so a recomposition mid-tracking doesn't recount.
    val appState = viewModel.appState
    var wasTracking by remember { mutableStateOf(false) }
    LaunchedEffect(appState) {
        if (appState == 2 && !wasTracking) {
            viewModel.incrementReviewTrackCount()
        }
        wasTracking = appState == 2
    }

    val activity = LocalContext.current as? android.app.Activity
    val reviewCount by viewModel.prefs.reviewTrackCount.collectAsState(initial = 0)
    val promptedVersion by viewModel.prefs.reviewPromptedVersion.collectAsState(initial = BuildConfig.VERSION_NAME)
    var reviewPrompted by remember { mutableStateOf(false) }
    LaunchedEffect(appState, reviewCount, promptedVersion) {
        if (appState == 2 && !reviewPrompted && activity != null &&
            ReviewGate.shouldPrompt(reviewCount, promptedVersion, BuildConfig.VERSION_NAME)
        ) {
            reviewPrompted = true
            viewModel.markReviewPrompted(BuildConfig.VERSION_NAME)
            ReviewLauncher.launch(activity)
        }
    }

    var showSettings by remember { mutableStateOf(false) }
    var settingsFocusWatch by remember { mutableStateOf(false) }
    var showAttribution by remember { mutableStateOf(false) }

    // targetSdk 35 forces edge-to-edge, so inset the content below the status
    // bar and above the nav bar (the Surface background still fills behind them).
    Box(Modifier.fillMaxSize().systemBarsPadding()) {
        when (viewModel.appState) {
            2 -> TrackingScreen(viewModel)
            3 -> InactiveScreen(onResume = { viewModel.resumeFromInactive() })
            else -> StationScreen(
                viewModel,
                onOpenSettings = { focusWatch ->
                    settingsFocusWatch = focusWatch
                    showSettings = true
                },
            )
        }
    }

    if (viewModel.showStationPicker) {
        StationPickerSheet(viewModel)
    }
    if (showSettings) {
        SettingsSheet(
            viewModel,
            focusWatch = settingsFocusWatch,
            onOpenAttribution = { showSettings = false; showAttribution = true },
            onDismiss = { showSettings = false },
        )
    }
    if (showAttribution) {
        AttributionSheet(onDismiss = { showAttribution = false })
    }

    // First-launch walkthrough sits above everything until completed or skipped.
    // It never auto-shows again once seen; a snackbar points to the Settings replay.
    val snackbarHostState = remember { SnackbarHostState() }
    val snackbarScope = rememberCoroutineScope()
    val hasSeenOnboarding by viewModel.prefs.hasSeenOnboarding.collectAsState(initial = true)
    if (!hasSeenOnboarding) {
        OnboardingTour(
            onComplete = {
                viewModel.markOnboardingSeen()
                snackbarScope.launch {
                    snackbarHostState.showSnackbar("You can replay the tour anytime in Settings.")
                }
            },
        )
    }

    Box(Modifier.fillMaxSize().systemBarsPadding(), contentAlignment = Alignment.BottomCenter) {
        SnackbarHost(snackbarHostState)
    }
}
