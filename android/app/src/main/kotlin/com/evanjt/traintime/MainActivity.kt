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
import androidx.compose.foundation.layout.Column
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
import com.evanjt.traintime.review.ReviewLauncher
import com.evanjt.traintime.ui.BackgroundLocationDeniedDialog
import com.evanjt.traintime.ui.BackgroundLocationDisclosureDialog
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.onboarding.CURRENT_TOUR_VERSION
import com.evanjt.traintime.ui.onboarding.OnboardingTour
import com.evanjt.traintime.ui.onboarding.effectiveSeenVersion
import com.evanjt.traintime.ui.onboarding.stepsToShow
import com.evanjt.traintime.ui.onboarding.tourSteps
import com.evanjt.traintime.ui.pending.PendingRouteChip
import com.evanjt.traintime.ui.pending.ReplaceRouteDialog
import com.evanjt.traintime.ui.pending.RouteDetailSheet
import com.evanjt.traintime.ui.settings.AttributionSheet
import com.evanjt.traintime.ui.settings.ReviewPromptDialog
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

    // Contextual ask when the first pending route is saved; denial is fine,
    // the chip and resume prompt work without the reminder.
    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    private fun requestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Background location for distance-aware reminders. On API 30+ the system
    // routes this to the "Allow all the time" settings screen when fine location
    // is already granted; a denial just leaves the reminder foreground-only.
    private val backgroundLocationLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            val granted = android.os.Build.VERSION.SDK_INT < 29 ||
                checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            viewModel.onBackgroundLocationResult(granted)
        }

    private fun openAppSettings() {
        startActivity(
            android.content.Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.fromParts("package", packageName, null),
            ),
        )
    }

    private fun requestBackgroundLocationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 29 &&
            checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            backgroundLocationLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }
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
                    RootView(
                        viewModel,
                        onRequestNotificationPermission = ::requestNotificationPermission,
                        onRequestBackgroundLocation = ::requestBackgroundLocationPermission,
                        onOpenAppSettings = ::openAppSettings,
                    )
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

        handleIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncoming(intent)
    }

    private fun handleIncoming(intent: Intent?) {
        if (intent == null) return
        // SBB shares the trip as an image + the link in EXTRA_TEXT, so the
        // intent type is image/*, not text/plain. Accept either and pull the
        // link from the text; the image stream is ignored.
        if (intent.action == Intent.ACTION_SEND) {
            val shared = intent.getStringExtra(Intent.EXTRA_TEXT)
                ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            if (shared != null) {
                viewModel.handleSharedText(shared)
                return
            }
        }
        intent.data?.let { viewModel.handleDeepLink(it) }
    }
}

@Composable
private fun RootView(
    viewModel: MainViewModel,
    onRequestNotificationPermission: () -> Unit,
    onRequestBackgroundLocation: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
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

    // Timed review ask. The VM counts real board taps and flips
    // showReviewPrompt at most once per version; this only renders it.
    val activity = LocalContext.current as? android.app.Activity
    if (viewModel.showReviewPrompt) {
        ReviewPromptDialog(
            onRate = {
                viewModel.dismissReviewPrompt()
                activity?.let { ReviewLauncher.openStoreListing(it) }
            },
            onNotNow = {
                viewModel.dismissReviewPrompt()
                viewModel.snoozeReview()
            },
            onNever = {
                viewModel.dismissReviewPrompt()
                viewModel.optOutReview()
            },
        )
    }

    var showSettings by remember { mutableStateOf(false) }
    var settingsFocusWatch by remember { mutableStateOf(false) }
    var showAttribution by remember { mutableStateOf(false) }
    var showRoute by remember { mutableStateOf(false) }

    // targetSdk 35 forces edge-to-edge, so inset the content below the status
    // bar and above the nav bar (the Surface background still fills behind them).
    Box(Modifier.fillMaxSize().systemBarsPadding()) {
        Column(Modifier.fillMaxSize()) {
            // Queued shared route rides above the station/inactive screens and
            // hides during tracking.
            val pendingRoute = viewModel.pendingRoute
            if (pendingRoute != null && viewModel.appState != 2) {
                var chipNow by remember { mutableStateOf(System.currentTimeMillis() / 1000) }
                LaunchedEffect(pendingRoute) {
                    while (true) {
                        chipNow = System.currentTimeMillis() / 1000
                        kotlinx.coroutines.delay(30_000)
                    }
                }
                PendingRouteChip(
                    route = pendingRoute,
                    nowEpochSeconds = chipNow,
                    plan = viewModel.reminderPlan,
                    onTap = { showRoute = true },
                    onDismiss = { viewModel.dismissPendingRoute() },
                )
            }
            Box(Modifier.weight(1f)) {
                when (viewModel.appState) {
                    2 -> TrackingScreen(viewModel)
                    // Keep the last board visible, darkened, with Resume floating
                    // on top rather than blanking it.
                    3 -> Box(Modifier.fillMaxSize()) {
                        StationScreen(
                            viewModel,
                            onOpenSettings = { focusWatch ->
                                settingsFocusWatch = focusWatch
                                showSettings = true
                            },
                        )
                        InactiveScreen(onResume = { viewModel.resumeToStationView() })
                    }
                    else -> StationScreen(
                        viewModel,
                        onOpenSettings = { focusWatch ->
                            settingsFocusWatch = focusWatch
                            showSettings = true
                        },
                    )
                }
            }
        }
    }

    // Whole-route view: every connection, per-connection reminder toggle, Track now.
    val routeForSheet = viewModel.pendingRoute
    if (showRoute && routeForSheet != null) {
        LaunchedEffect(routeForSheet.id) { viewModel.loadRoutePlatforms(routeForSheet) }
        RouteDetailSheet(
            route = routeForSheet,
            mode = viewModel.currentMode,
            platforms = viewModel.routeLegPlatforms,
            onSetMuted = { index, muted -> viewModel.setLegMuted(index, muted) },
            onTrackLeg = { index -> viewModel.trackLeg(index) },
            onDismiss = { showRoute = false },
        )
    }

    // Contextual notification-permission ask for the first saved route.
    LaunchedEffect(viewModel.notificationPermissionRequest) {
        if (viewModel.notificationPermissionRequest) {
            onRequestNotificationPermission()
            viewModel.clearNotificationPermissionRequest()
        }
    }

    // Background-location ask when the user opts into background distance tracking.
    // Google Play requires a prominent disclosure before the system prompt, so gate
    // the request behind an explicit consent dialog rather than launching directly.
    if (viewModel.backgroundLocationRequest) {
        BackgroundLocationDisclosureDialog(
            onContinue = {
                viewModel.clearBackgroundLocationRequest()
                onRequestBackgroundLocation()
            },
            onDismiss = { viewModel.clearBackgroundLocationRequest() },
        )
    }

    // Declined "all the time": reassure it still works from the last known
    // location, and offer a one-tap path to grant it later.
    if (viewModel.backgroundLocationDenied) {
        BackgroundLocationDeniedDialog(
            onOpenSettings = {
                viewModel.clearBackgroundLocationDenied()
                onOpenAppSettings()
            },
            onDismiss = { viewModel.clearBackgroundLocationDenied() },
        )
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

    // Shared-route intake feedback + replace confirmation.
    viewModel.shareReplaceOffer?.let { offer ->
        ReplaceRouteDialog(
            destination = offer.route.finalDestinationName,
            onReplace = { viewModel.confirmReplaceSharedRoute() },
            onDismiss = { viewModel.dismissReplaceSharedRoute() },
        )
    }

    // First-launch walkthrough sits above everything until completed or skipped.
    // A new install sees the full tour; an updater sees only steps added since
    // they last finished it. A snackbar points to the Settings replay.
    val snackbarHostState = remember { SnackbarHostState() }
    val snackbarScope = rememberCoroutineScope()
    val hasSeenOnboarding by viewModel.prefs.hasSeenOnboarding.collectAsState(initial = true)
    val seenVersion by viewModel.prefs.seenOnboardingVersion.collectAsState(initial = CURRENT_TOUR_VERSION)
    val tourSlice = stepsToShow(
        tourSteps,
        effectiveSeenVersion(hasSeenOnboarding, seenVersion),
        CURRENT_TOUR_VERSION,
    )
    if (tourSlice.isNotEmpty()) {
        OnboardingTour(
            steps = tourSlice,
            onComplete = {
                viewModel.markOnboardingSeen()
                snackbarScope.launch {
                    snackbarHostState.showSnackbar("You can replay the tour anytime in Settings.")
                }
            },
        )
    }

    val shareStatus = viewModel.shareStatus
    LaunchedEffect(shareStatus) {
        if (shareStatus != null) {
            snackbarHostState.showSnackbar(shareStatus)
            viewModel.clearShareStatus()
        }
    }

    Box(Modifier.fillMaxSize().systemBarsPadding(), contentAlignment = Alignment.BottomCenter) {
        SnackbarHost(snackbarHostState)
    }
}
