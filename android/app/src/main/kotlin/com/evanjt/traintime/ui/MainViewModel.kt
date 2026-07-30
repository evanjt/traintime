package com.evanjt.traintime.ui

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import androidx.glance.appwidget.updateAll
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.glance.appwidget.updateAll
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.evanjt.traintime.BuildConfig
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.GarminConnectIQService
import com.evanjt.traintime.SwissBounds
import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.Timing
import com.evanjt.traintime.data.api.TrainApi
import com.evanjt.traintime.data.api.TrainApiException
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Favourite
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.GpsQuality
import com.evanjt.traintime.data.model.LatLon
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.model.PinnedStation
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.sbb.SbbDecodeException
import com.evanjt.traintime.data.sbb.SbbShareLink
import com.evanjt.traintime.data.sbb.SbbShareService
import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import com.evanjt.traintime.data.sbb.SharedRoute
import com.evanjt.traintime.data.sbb.matchDeparture
import com.evanjt.traintime.core.sync.TrackCommand
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.core.sync.WearStateSync
import com.evanjt.traintime.core.sync.WearCommand
import com.evanjt.traintime.core.sync.WearLivenessBus
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.review.ReviewGate
import com.evanjt.traintime.session.TrackingLogic
import com.evanjt.traintime.session.TrackingNotificationService
import com.evanjt.traintime.session.TrackingSessionBus
import com.evanjt.traintime.session.TrackingSnapshot
import com.evanjt.traintime.ui.onboarding.CURRENT_TOUR_VERSION
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.data.prefs.MyStationsStore
import com.evanjt.traintime.data.prefs.PendingRouteStore
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.HapticService
import com.evanjt.traintime.domain.LocationService
import com.evanjt.traintime.domain.PendingRouteLogic
import com.evanjt.traintime.notify.NotifyPlan
import com.evanjt.traintime.notify.PendingRouteNotifier
import com.evanjt.traintime.notify.RouteDistanceTracker
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class TrackingStatus { NO_GPS, AHEAD, ON_TIME, BEHIND }

// Port of apple/TrainTimePhone/ViewModels/PhoneViewModel.swift.
// appState: 0 = station view, 2 = focused tracking, 3 = inactive.
enum class PhoneWatchType { WEAR, GARMIN }

// A watch the phone can send to. Wear OS arrives over the Data Layer; Garmin over the
// Connect IQ Mobile SDK. Mirrors iOS PhoneConnectedWatch.
data class ConnectedWatch(val id: String, val name: String, val type: PhoneWatchType)

// A paired watch and whether it's reachable now, for the settings link-status display.
data class WatchLink(val name: String, val type: PhoneWatchType, val connected: Boolean)

// OEMs whose battery managers kill foreground services in the background
// unless the app is exempted (the dontkillmyapp.com offenders).
private val AGGRESSIVE_OEMS = setOf(
    "oneplus", "oppo", "realme", "xiaomi", "redmi", "poco", "vivo", "iqoo",
    "huawei", "honor", "samsung", "meizu", "asus", "tecno", "infinix", "blackview",
)

class MainViewModel(application: Application) : AndroidViewModel(application) {

    // Localised string for VM status/snackbar/notification text. Pre-33 the
    // AppCompat override never reaches the application context, so resolve
    // against a context wrapped in the stored language tag.
    private var appLanguageTag = ""

    private fun str(id: Int, vararg args: Any): String =
        com.evanjt.traintime.domain.LocaleUtil
            .localised(getApplication(), appLanguageTag)
            .getString(id, *args)

    val prefs = AppPrefs(application)
    val favouritesStore = FavouritesStore(application)
    val myStationsStore = MyStationsStore(application)
    val pendingRouteStore = PendingRouteStore(application)
    val location = LocationService(application, prefs)
    val haptics = HapticService(application)
    private val api = TrainApi.shared
    private val wearSync = WearStateSync.get(application)
    val garminService = GarminConnectIQService(application)

    // App state
    var appState by mutableStateOf(0)
        private set
    var status by mutableStateOf(str(CoreR.string.status_gps_searching))
        private set

    // Gates the faint Swiss-outline backdrop (and marks the out-of-Switzerland
    // status). Replaces the old string-equality check on the status text, which
    // broke once status became localised.
    var isOutOfBounds by mutableStateOf(false)
        private set

    // Station data (per mode)
    var trainStations by mutableStateOf(listOf<Station>())
        private set
    var busStations by mutableStateOf(listOf<Station>())
        private set
    var tramStations by mutableStateOf(listOf<Station>())
        private set
    var specialStations by mutableStateOf(listOf<Station>())
        private set
    var stationIndex by mutableStateOf(0)
        private set

    // Transport modes
    var currentMode by mutableStateOf(TransportMode.TRAIN)
        private set
    var availableModes by mutableStateOf(listOf<TransportMode>())
        private set
    var defaultMode by mutableStateOf(TransportMode.TRAIN)
        private set

    // Departures
    var departures by mutableStateOf(listOf<Departure>())
        private set
    var favouriteDepartures by mutableStateOf(listOf<Departure>())
        private set
    var favouritesList by mutableStateOf(listOf<Favourite>())
        private set

    // Pinned "My stations", bubble to the front of the nearby list.
    var pinnedStations by mutableStateOf(listOf<PinnedStation>())
        private set
    var pinnedStationIds by mutableStateOf(setOf<String>())
        private set

    // Selection & tracking
    var showStationPicker by mutableStateOf(false)
    var focusedTrain by mutableStateOf<FocusedDeparture?>(null)
        private set
    var formation by mutableStateOf<Formation?>(null)
        private set

    // Timed review ask, set at most once per version by a real board tap
    // (maybeRequestReview) and rendered by RootView.
    var showReviewPrompt by mutableStateOf(false)
        private set

    // Connected watches (Wear + Garmin) + last send status, for the "Send to Watch" control.
    var connectedWatches by mutableStateOf(listOf<ConnectedWatch>())
        private set

    // Paired watches with live status, for the Settings link-status row.
    var watchLinks by mutableStateOf(listOf<WatchLink>())
        private set
    var watchSendStatus by mutableStateOf<String?>(null)
        private set

    // GPS
    var gpsQuality by mutableStateOf(GpsQuality.UNAVAILABLE)
        private set
    var lastWalkDist by mutableStateOf(0.0)
        private set
    private var lastWalkTime: Double? = null

    // Internal state
    private var requestInFlight = false
    private var requestStartTime: Long? = null
    private var lastFetchTime = 0L
    private var lastSearchCoordinate: LatLon? = null
    private var consecutiveErrors = 0
    private var lastVibeTick = 0L
    private var loadedFromCache = false
    private var lastInteractionTime = now()
    private var pendingDeepLink: Uri? = null
    private var timerJob: Job? = null

    // Shared SBB route intake. pendingShareTrack is one-shot: the departures
    // fetch it triggered consumes it, so an unrelated board can't auto-track.
    var shareStatus by mutableStateOf<String?>(null)
        private set
    var shareReplaceOffer by mutableStateOf<SharedRouteOffer?>(null)
        private set
    private var pendingShareTrack: SharedRouteOffer? = null

    // Queued shared route (store-mirrored) + the resume prompt when its leg
    // is on the live board. notificationPermissionRequest is a one-shot UI
    // event: tracking starts and saved routes ask contextually (API 33+).
    var pendingRoute by mutableStateOf<PendingRoute?>(null)
        private set
    var notificationPermissionRequest by mutableStateOf(false)
        private set

    // The visible station was launched directly (shared route / resume), not
    // from a nearby search at the user's location. On exit we must re-search
    // at real GPS instead of stranding them on the remote origin.
    private var launchedStationActive = false

    // Garmin mirroring (optional overlay; off → the watch runs entirely on its own).
    // Cached eligible Garmin device IDs so mirror pushes skip a per-change BLE
    // app-installed sweep; refreshed whenever watch links are.
    private var garminTargetIds: List<String> = emptyList()
    private var mirrorToWatch = true
    private var mirrorJob: Job? = null
    private var lastPushedLoc: LatLon? = null
    private var lastLocPushTime = 0L

    // Watch-app liveness, per backend (Garmin over Connect IQ, Wear over the Data
    // Layer, same hello/alive/bye contract). The watch announces itself; the phone
    // never pings (a phone message can wake a closed watch-app). A fresh alive →
    // green, a stale one or a bye → amber, and a press shows the spinner until the
    // watch says hello. watchAlive is the combined indicator the UI renders.
    private var heartbeatJob: Job? = null
    private var garminLastAlive = 0L
    // Ping-gate bookkeeping, persisted across launches: the freshest signal ever
    // heard (bye does not zero it, unlike garminLastAlive), the last bye, and the
    // watch's protocol version. Together they say "the watch app is probably
    // still open", the only case where a foreground ping is safe.
    private var garminLastAliveHighWater = 0L
    private var garminLastBye = 0L
    private var garminWatchPv = 0
    private var garminLinkStateLoaded = false
    // Version last announced by the Garmin watch over the Connect IQ liveness
    // hello/alive (null until first heard). Same gate as Wear: a pre-versioning
    // Garmin build sends no version and reads as 0.4.x.
    private var garminWatchVersion: String? = null
    private var wearLastAlive = 0L
    private var wearNodesPresent = false
    private var hasKnownWearNode = false
    // Version last announced by the connected Wear watch (null until first
    // liveness). Drives the Send-to-Watch update guard and the "please update"
    // copy. A pre-versioning watch reports LEGACY_VERSION_NAME (0.4.x).
    private var wearWatchVersion: String? = null
    private var wearMirrorJob: Job? = null
    var watchChecking by mutableStateOf(false)
        private set
    var watchAlive by mutableStateOf(false)
        private set
    // A watch is paired but not currently connected (off / out of range) → grey.
    var watchKnownButDisconnected by mutableStateOf(false)
        private set

    // Departure the watch reports it is tracking: set by trackStarted and by
    // trk/trkLn on the pv>=3 liveness heartbeat, cleared by trackEnded, bye and
    // liveness loss. This is what flips "Track on watch" to "Tracking on watch".
    var watchTrackingDepTs by mutableStateOf<Long?>(null)
        private set
    var watchTrackingLine by mutableStateOf<String?>(null)
        private set
    // Full trackStarted payload when we saw one (the heartbeat only carries
    // depTs/line). Needed to rebuild a FocusedDeparture for tap-to-follow.
    private var watchTrackingInfo: Map<String, Any?>? = null
    // Which backend announced the tracking, so only its own liveness can
    // confirm or clear the claim.
    private var watchTrackingSource: PhoneWatchType? = null
    private var wearWatchPv = 0
    // The user asked to track on a closed watch: openWatchApp is in flight and
    // the next hello must carry the track command first. Without this, a stale
    // alive reading used to route the tap into a send the closed app never saw.
    private var pendingWatchTrackSend = false

    // The watch is tracking the same departure the phone is focused on.
    val watchTrackingFocused: Boolean
        get() {
            val focused = focusedTrain ?: return false
            val depTs = watchTrackingDepTs ?: return false
            val line = watchTrackingLine
            return focused.departureTimestamp == depTs &&
                (line.isNullOrEmpty() || focused.lineNumber == line)
        }

    private fun clearWatchTracking() {
        watchTrackingDepTs = null
        watchTrackingLine = null
        watchTrackingInfo = null
        watchTrackingSource = null
    }

    // "IC 8 → Brig · 14:54" for the station-view chip; built from the last
    // trackStarted payload, or just line + time when only the heartbeat spoke.
    val watchTrackingLabel: String?
        get() {
            val depTs = watchTrackingDepTs ?: return null
            val info = watchTrackingInfo
            val line = (info?.get("line") as? String).takeUnless { it.isNullOrEmpty() } ?: watchTrackingLine
            val dest = (info?.get("dest") as? String).takeUnless { it.isNullOrEmpty() }
            val time = DateTimeFormatter.ofPattern("HH:mm")
                .format(Instant.ofEpochSecond(depTs).atZone(ZoneId.systemDefault()))
            val head = listOfNotNull(line.takeUnless { it.isNullOrEmpty() }, dest?.let { "→ $it" })
                .joinToString(" ")
            return if (head.isEmpty()) time else "$head · $time"
        }

    val watchTrackingFollowable: Boolean
        get() {
            val info = watchTrackingInfo ?: return false
            return (info["depTs"] as? Number)?.toLong() == watchTrackingDepTs &&
                !(info["dest"] as? String).isNullOrEmpty()
        }

    // Enter the phone's tracking view on the departure the watch is tracking,
    // without mirroring back (the watch already owns this track).
    fun followWatchTracking() {
        val depTs = watchTrackingDepTs ?: return
        val info = watchTrackingInfo ?: return
        if ((info["depTs"] as? Number)?.toLong() != depTs) return
        beginTracking(
            FocusedDeparture(
                destination = info["dest"] as? String ?: return,
                departureTimestamp = depTs,
                lineNumber = info["line"] as? String ?: "",
                category = info["cat"] as? String ?: "",
                trainNumber = info["trainNum"] as? String,
                operatorRef = info["opRef"] as? String,
                delay = (info["delay"] as? Number)?.toInt() ?: 0,
                platform = info["plat"] as? String ?: "",
                platformChanged = info["platChg"] as? Boolean ?: false,
            ),
            mirror = false,
        )
    }

    private fun now(): Long = System.currentTimeMillis()
    private fun nowSeconds(): Long = now() / 1000

    // Computed
    val stations: List<Station>
        get() = when (currentMode) {
            TransportMode.TRAIN -> trainStations
            TransportMode.BUS -> busStations
            TransportMode.TRAM -> tramStations
            TransportMode.SPECIAL -> specialStations
        }

    val currentStation: Station?
        get() = stations.getOrNull(stationIndex)

    val walkInfo: String
        get() = currentStation?.walkInfo(
            com.evanjt.traintime.domain.LocaleUtil.localised(getApplication(), appLanguageTag),
            stationIndex,
            stations.size,
        ) ?: ""

    val stationName: String
        get() = currentStation?.name ?: str(CoreR.string.station_fallback)

    init {
        viewModelScope.launch { prefs.appLanguage.collect { appLanguageTag = it } }
        // Garmin watch link (no-op unless the Connect IQ SDK is linked + a watch paired).
        garminService.onMessageReceived = { ctx -> applyReceivedWatchContext(ctx) }
        // Live status: a watch connecting/disconnecting (e.g. Bluetooth toggled) re-checks
        // eligibility, so the header indicator and settings update without reopening the app.
        garminService.onLinkChanged = { refreshWatchLinks() }
        garminService.initialize()

        viewModelScope.launch { prefs.mirrorToWatch.collect { mirrorToWatch = it } }
        viewModelScope.launch { prefs.ensureFirstLaunchTimestamp() }
        viewModelScope.launch { prefs.hasKnownWearNode.collect { hasKnownWearNode = it } }
        viewModelScope.launch {
            pendingRouteStore.pending.collect {
                pendingRoute = it
                // A watch-sent route (or any store change) computes the reminder
                // readout straight away, instead of waiting for the next
                // foreground to run syncReminderTracking via onAppear.
                syncReminderTracking()
                // Mirror to the watch chip; the echo guard absorbs no-ops.
                runCatching { wearSync.pushState() }
            }
        }

        // Wear liveness (hello/alive/bye/reqLoc) relayed by PhoneWearListenerService,
        // the Data Layer peer of the Garmin path through applyReceivedWatchContext.
        viewModelScope.launch { WearLivenessBus.events.collect { handleWearLiveness(it) } }

        // The tracking notification's "Stop tracking" action, so a reopened app
        // doesn't resurrect a session the user ended from the shade.
        viewModelScope.launch {
            TrackingSessionBus.stopRequests.collect {
                if (appState == 2) exitToStationView() else clearBackgroundTracking()
            }
        }

        viewModelScope.launch {
            defaultMode = prefs.defaultModeNow()
            currentMode = defaultMode
        }
        viewModelScope.launch {
            // Keep the default mode live and synced, a watch-originated change
            // arrives through this flow once the listener service writes it.
            prefs.defaultMode.collect {
                defaultMode = it
                wearSync.pushState()
            }
        }
        viewModelScope.launch {
            // Re-extract the top section immediately on a toggle rather than waiting
            // for the next fetch (the 30 s cooldown), and refresh star tints.
            favouritesStore.favourites.collect {
                favouritesList = it
                favouriteDepartures = extractFavouritesFromCurrent(departures)
                wearSync.pushState()
                pushFavouritesToGarmin(it)
            }
        }
        viewModelScope.launch {
            // Keep pinned stations live: reorder the loaded lists so pins stay at
            // the front the moment the set changes (no refetch needed).
            myStationsStore.stations.collect { list ->
                pinnedStations = list
                pinnedStationIds = list.map { it.id }.toSet()
                applyPinnedReorder()
                wearSync.pushState()
            }
        }
        viewModelScope.launch {
            location.coordinate.collect { onLocationUpdate(it) }
        }
        viewModelScope.launch {
            location.authorizationDenied.collect { denied ->
                if (denied && stations.isEmpty()) {
                    status = str(CoreR.string.status_location_permission)
                    isOutOfBounds = false
                }
            }
        }
    }

    // Lifecycle

    fun onAppear() {
        lastInteractionTime = now()
        // The tracking service's own loop idles while we own the fetching.
        TrackingSessionBus.appForeground.value = true
        viewModelScope.launch {
            location.start()
            if (location.loadedFromCache) loadedFromCache = true
        }
        startTimer(if (appState == 2) Timing.TRACKING_REFRESH_INTERVAL else Timing.NORMAL_REFRESH_INTERVAL)
        refreshWatchLinksOnAppear()
        viewModelScope.launch { refreshPendingRoute() }
        syncReminderTracking()
        maybeShowBgLocationIntro()
    }

    // On foreground: find eligible watches (connected + TrainTime installed) for the header
    // indicator and settings list, then feed the current location to any already-open watch.
    // The BLE sweep finishes after the first location emits, so without this push a watch
    // sitting on "Not in Switzerland" would never pick up the phone's position until it moved.
    private fun refreshWatchLinksOnAppear() {
        viewModelScope.launch {
            val wearNames = wearSync.connectedWatchNames()
            noteWearNodes(wearNames)
            val wear = wearNames.map { WatchLink(it, PhoneWatchType.WEAR, true) }
            val garmin = garminService.eligibleDevices()
            garminTargetIds = garmin.map { it.id }
            watchLinks = wear + buildGarminLinks(garmin)
            updateKnownButDisconnected()
            persistGarminEverConnected()
            pushLocationNow()
            startHeartbeat()
            maybePingGarmin()
        }
    }

    // Accelerate the green indicator when the phone foregrounds while the watch
    // app is probably still open: ask it to say hello now instead of waiting out
    // its heartbeat. Hard-gated (see WearSync.shouldPingGarmin), because a phone
    // message can wake a closed Garmin watch-app.
    private suspend fun maybePingGarmin() {
        ensureGarminLinkState()
        if (!mirrorToWatch || garminTargetIds.isEmpty() || garminAliveFresh()) return
        if (!WearSync.shouldPingGarmin(garminLastAliveHighWater, garminLastBye, now(), garminWatchPv)) return
        val payload = WearSync.garminPingPayload()
        garminTargetIds.forEach { garminService.send(it, payload) }
    }

    private suspend fun ensureGarminLinkState() {
        if (garminLinkStateLoaded) return
        garminLinkStateLoaded = true
        val (alive, bye, pv) = prefs.garminLinkState()
        if (garminLastAliveHighWater == 0L) garminLastAliveHighWater = alive
        if (garminLastBye == 0L) garminLastBye = bye
        if (garminWatchPv == 0) garminWatchPv = pv
    }

    private suspend fun persistGarminLinkState() {
        prefs.saveGarminLinkState(garminLastAliveHighWater, garminLastBye, garminWatchPv)
    }

    private suspend fun noteWearNodes(names: List<String>) {
        wearNodesPresent = names.isNotEmpty()
        if (wearNodesPresent && !hasKnownWearNode) prefs.markKnownWearNode()
    }

    // Launch TrainTime on the connected Garmin watch(es), the one place we legitimately
    // wake the watch, because the user asked. Then feed the current location so it lands
    // inside Switzerland straight away. Shows the spinner until the watch announces itself
    // (green) or a timeout elapses (amber). openApp is best-effort over BLE; tap again to retry.
    fun openWatchApp() {
        viewModelScope.launch {
            val garmin = garminService.eligibleDevices()
            garminTargetIds = garmin.map { it.id }
            if (garmin.isEmpty()) {
                watchChecking = false
                watchAlive = false
                showWatchStatus(str(R.string.no_watch_connected))
                return@launch
            }
            // Already open, just push the current view to it, no relaunch needed.
            if (watchAlive) {
                if (pendingWatchTrackSend) {
                    pendingWatchTrackSend = false
                    sendFocusedTrackFirst()
                } else {
                    syncCurrentStateToWatch()
                }
                return@launch
            }
            watchChecking = true
            garmin.forEach { garminService.openApp(it.id) }
            // The watch sends "hello" once it starts, which flips us to alive and triggers
            // a state sync. Give it a window; if nothing arrives, settle to amber.
            delay(8000)
            if (watchChecking) {
                watchChecking = false
                recomputeWatchAlive()
            }
        }
    }

    // Reminder "Send to Watch" action (traintime://sendtowatch). The app is now
    // foreground, so Connect IQ can bind (it won't from a background service). Wait
    // for the bind, wake the watch app, then push the saved route's current leg once
    // it announces itself, with one retry to cover a send racing the cold start.
    fun sendPendingRouteToWatch() {
        viewModelScope.launch {
            garminService.initialize()
            val route = pendingRouteStore.current()
                ?.let { PendingRouteLogic.normalize(it, nowSeconds()) } ?: return@launch
            val leg = route.currentLeg ?: return@launch
            val payload = TrackCommand.fromLeg(leg, route.finalDestination).toGarminMap()

            // The bind is async even in the foreground; wait for it before querying.
            val sdkDeadline = now() + 12_000
            while (now() < sdkDeadline && !garminService.isAvailable) delay(200)

            // eligibleDevices does a per-device BLE app-info query with no timeout;
            // a paired-but-unreachable watch would hang it. Bound it so we always
            // fall through to the "no watch" hint.
            val garmin = withTimeoutOrNull(6_000) { garminService.eligibleDevices() } ?: emptyList()
            garminTargetIds = garmin.map { it.id }
            if (garmin.isEmpty()) {
                showWatchStatus(str(R.string.no_watch_connected))
                return@launch
            }

            // Wake the app, wait for its hello (flips garminAliveFresh), then send
            // + retry to cover a send racing the cold start.
            garmin.forEach { garminService.openApp(it.id) }
            val aliveDeadline = now() + 8_000
            while (now() < aliveDeadline && !garminAliveFresh()) delay(300)
            garminTargetIds.forEach { garminService.send(it, payload) }
            delay(2_000)
            garminTargetIds.forEach { garminService.send(it, payload) }
            // Re-open once the track has landed: a launch issued while the watch was
            // in its phone-notification view often doesn't foreground the app, so a
            // second open pulls the now-tracking app to the front. Best-effort — the
            // watch may still keep the notification view on top (a Garmin OS call).
            delay(500)
            garminTargetIds.forEach { garminService.openApp(it) }
            showWatchStatus(str(R.string.sent_to_watch))
        }
    }

    // Passive liveness ticker. We never ping the watch (a phone message can wake a closed
    // watch-app on Garmin); the watch announces itself with hello/alive/bye and this only
    // recomputes the colour from the freshest signal. Sends nothing.
    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = viewModelScope.launch {
            while (true) {
                if (!watchChecking) {
                    recomputeWatchAlive()
                    // Grey when a watch is paired but not reachable. knownDevices is a local
                    // SDK lookup (no BLE), so it's cheap to re-evaluate each tick.
                    updateKnownButDisconnected()
                    // A dead heartbeat takes the tracking claim with it: better
                    // no indicator than a stale "Tracking on watch".
                    val trackingStale = when (watchTrackingSource) {
                        PhoneWatchType.GARMIN -> !garminAliveFresh()
                        PhoneWatchType.WEAR -> !wearAliveFresh()
                        null -> false
                    }
                    if (watchTrackingDepTs != null && trackingStale) clearWatchTracking()
                }
                delay(3000)
            }
        }
    }

    // Connected Garmin devices render as live links; paired-but-disconnected ones render
    // as grey "not connected" so the user knows the watch is known but currently off/away.
    private fun buildGarminLinks(connected: List<GarminConnectIQService.GarminDevice>): List<WatchLink> {
        val connectedIds = connected.map { it.id }.toSet()
        val live = connected.map { WatchLink(it.name, PhoneWatchType.GARMIN, true) }
        val disconnected = garminService.knownDeviceNames()
            .filter { it.id !in connectedIds }
            .map { WatchLink(it.name, PhoneWatchType.GARMIN, false) }
        return live + disconnected
    }

    private fun updateKnownButDisconnected() {
        watchKnownButDisconnected = garminTargetIds.isEmpty() && !wearNodesPresent && !watchAlive &&
            (garminService.hasKnownDevices() || hasKnownWearNode)
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    // An alive/hello within the last few heartbeat intervals counts as alive (the watch
    // beats every ~7s, so tolerate a couple of drops). Same threshold as iOS.
    private fun garminAliveFresh(): Boolean = now() - garminLastAlive <= 20_000
    private fun wearAliveFresh(): Boolean = now() - wearLastAlive <= 20_000

    private fun recomputeWatchAlive() {
        watchAlive = (garminTargetIds.isNotEmpty() && garminAliveFresh()) ||
            (wearNodesPresent && wearAliveFresh())
    }

    // Wear liveness announcements, the Data Layer peer of the hello/alive/bye
    // handling for Garmin in applyReceivedWatchContext. The raw payload carries
    // the watch's version (see WearSync.decodeLiveness); a bare kind string is a
    // pre-versioning watch.
    private fun handleWearLiveness(raw: String) {
        val msg = WearSync.decodeLiveness(raw)
        when (msg.kind) {
            WearSync.KIND_HELLO, WearSync.KIND_ALIVE -> {
                wearWatchVersion = msg.displayVersion
                wearWatchPv = msg.pv
                val wasAlive = wearAliveFresh()
                wearLastAlive = now()
                wearNodesPresent = true
                recomputeWatchAlive()
                // pv>=2 heartbeats carry the tracked departure; absence on such
                // a watch means "not tracking" (older watches stay edge-driven).
                if (msg.trk != null) {
                    if ((watchTrackingInfo?.get("depTs") as? Number)?.toLong() != msg.trk) {
                        watchTrackingInfo = msg.track?.toGarminMap()
                    }
                    watchTrackingDepTs = msg.trk
                    watchTrackingLine = msg.trkLn
                    watchTrackingSource = PhoneWatchType.WEAR
                } else if (msg.pv >= 2 && watchTrackingSource == PhoneWatchType.WEAR) {
                    clearWatchTracking()
                }
                // A freshly-online watch jumps to whatever the phone is showing.
                if (!wasAlive) syncCurrentStateToWear()
            }
            WearSync.KIND_BYE -> {
                wearLastAlive = 0L
                recomputeWatchAlive()
                if (watchTrackingSource == PhoneWatchType.WEAR) clearWatchTracking()
            }
            WearSync.KIND_REQ_LOC -> replyWithLocationToWear()
            WearSync.KIND_TRACK_STARTED -> {
                // The watch entered tracking (its own tap, or the echo of our
                // track command — the echo doubles as the delivery ack).
                watchTrackingDepTs = msg.trk
                watchTrackingLine = msg.trkLn
                watchTrackingInfo = msg.track?.toGarminMap()
                watchTrackingSource = PhoneWatchType.WEAR
            }
            WearSync.KIND_TRACK_ENDED -> {
                if (watchTrackingSource != PhoneWatchType.GARMIN) clearWatchTracking()
            }
        }
    }

    fun onDisappear() {
        // Hand the tracking session to the service's loop: it fetches, walks and
        // renders the notification until onAppear takes it back.
        TrackingSessionBus.appForeground.value = false
        // The widget is only visible once we background; seed its cache with what
        // was on screen so it shows live data without its own refresh tap.
        seedWidgetCache()
        location.stop()
        stopTimer()
        stopHeartbeat()
        // The ping gate must survive a process death while backgrounded.
        viewModelScope.launch { persistGarminLinkState() }
    }

    fun onPermissionResult(granted: Boolean) {
        if (granted) {
            onAppear()
        } else {
            location.onPermissionDenied()
        }
    }

    // Timer

    private fun startTimer(intervalSeconds: Double) {
        stopTimer()
        timerJob = viewModelScope.launch {
            while (isActive) {
                delay((intervalSeconds * 1000).toLong())
                onTimerTick()
            }
        }
    }

    private fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }

    // Location update

    private fun onLocationUpdate(coord: LatLon?) {
        gpsQuality = location.gpsQuality

        if (coord == null) {
            if (stations.isEmpty()) {
                status = str(CoreR.string.status_gps_searching)
                isOutOfBounds = false
            }
            return
        }

        // Keep a connected watch fed with the phone's location as a GPS fallback.
        maybePushLocationToWatch(coord)

        if (!SwissBounds.contains(coord.lat, coord.lon) && stations.isEmpty()) {
            status = str(CoreR.string.status_not_in_switzerland)
            isOutOfBounds = true
            return
        }

        // Skip station search in tracking/inactive (still update GPS above)
        if (appState >= 2) return

        if (loadedFromCache && (location.gpsQuality == GpsQuality.GOOD || location.gpsQuality == GpsQuality.POOR)) {
            loadedFromCache = false
            if (!requestInFlight) {
                if (stations.isEmpty()) {
                    status = str(CoreR.string.status_updating_stations)
                    isOutOfBounds = false
                }
                fetchStations(coord.lat, coord.lon)
            }
            return
        }

        if (stations.isEmpty() && !requestInFlight) {
            status = str(CoreR.string.status_finding_stations)
            isOutOfBounds = false
            fetchStations(coord.lat, coord.lon)
        }
    }

    // Timer tick

    private fun onTimerTick() {
        gpsQuality = location.gpsQuality

        // Request timeout check
        val startTime = requestStartTime
        if (requestInFlight && startTime != null && now() - startTime > Timing.REQUEST_TIMEOUT * 1000) {
            requestInFlight = false
            requestStartTime = null
            if (appState == 2) consecutiveErrors += 1
        }

        // A background-tracked session that has departed: drop the board card
        // (the service's own loop ends and posts its "departed" card).
        backgroundTracked?.let {
            if (it.minutesUntil(nowSeconds()) < -1.0) clearBackgroundTracking()
        }

        val coord = location.coordinate.value ?: return

        // Movement detection (station view only): refresh in place
        val lastSearch = lastSearchCoordinate
        if (appState <= 1 && lastSearch != null && location.hasMovedSignificantly(lastSearch)) {
            fetchStations(coord.lat, coord.lon)
            return
        }

        // Update walk distance to current station. lat/lon are nullable :core
        // properties, so capture locals. Cross-module props don't smart-cast.
        val stationLat = currentStation?.lat
        val stationLon = currentStation?.lon
        if (stationLat != null && stationLon != null) {
            lastWalkDist = GeoUtils.haversineDistance(coord.lat, coord.lon, stationLat, stationLon)
            lastWalkTime = null
        }

        // State 2: auto-exit check and heartbeat
        if (appState == 2) {
            val focused = focusedTrain
            if (focused != null) {
                val minutesLeft = focused.minutesUntil(nowSeconds())
                // Departed >1 min ago: drop to the inactive tap-to-refresh state, not the
                // station view, so polling stops right away. The watch expires on its own depTs.
                if (minutesLeft < -1.0) {
                    haptics.shortPulse()
                    enterInactiveState()
                    return
                }

                val walkMin = lastWalkTime?.let { it / 60.0 } ?: GeoUtils.walkMinutes(lastWalkDist)
                val effectBuf = minutesLeft - walkMin + focused.delay.toDouble()
                if (effectBuf < -0.5) {
                    val nowS = nowSeconds()
                    val interval = if (effectBuf < -2.0) 2 else 4
                    if (nowS - lastVibeTick >= interval) {
                        haptics.heartbeat()
                        lastVibeTick = nowS
                    }
                }
                pushTrackingNotification()
            }
        }

        // Inactivity timeout in station view
        if (appState == 0 && now() - lastInteractionTime >= Timing.INACTIVITY_TIMEOUT * 1000) {
            enterInactiveState()
            return
        }

        if (appState == 3) return

        // Fetch departures if cooldown elapsed
        val cooldown = if (appState == 2) Timing.FETCH_COOLDOWN_TRACKING else Timing.FETCH_COOLDOWN_NORMAL
        if (!requestInFlight && now() - lastFetchTime >= cooldown * 1000) {
            val current = currentStation
            if (current != null) {
                fetchDepartures(current.id)
            } else if (stations.isEmpty() && SwissBounds.contains(coord.lat, coord.lon)) {
                fetchStations(coord.lat, coord.lon)
            }
        }
    }

    // Departure selection & tracking

    fun selectFavouriteDeparture(dep: Departure) {
        selectDepartureImpl(dep)
    }

    fun selectDeparture(index: Int) {
        departures.getOrNull(index)?.let { selectDepartureImpl(it) }
    }

    private fun selectDepartureImpl(dep: Departure, routeDestination: String? = null) {
        val depTs = dep.departureTimestamp ?: return
        if (dep.isGone) return
        beginTracking(
            FocusedDeparture(
                destination = dep.destination,
                departureTimestamp = depTs,
                lineNumber = dep.lineNumber,
                category = dep.category,
                trainNumber = dep.trainNumber,
                operatorRef = dep.operatorRef,
                delay = dep.delay,
                platform = dep.platform,
                platformChanged = dep.platformChanged,
                routeDestination = routeDestination,
            )
        )
        maybeRequestReview()
    }

    // Track a shared-route leg whose train isn't on the live board yet. The
    // countdown is fully local (derived from depTs), so it runs without a board
    // match; updateFocusedTrain keeps it until the train actually departs, then
    // a live board match upgrades it with delay/platform.
    private fun enterProtectedTrack(leg: RouteLeg, routeDestination: String? = null) {
        beginTracking(
            FocusedDeparture(
                // Best-effort until a live board match upgrades it to the train's
                // real terminus; the leg only carries its alight stop.
                destination = leg.destName,
                departureTimestamp = leg.depTs,
                lineNumber = leg.lineNumber ?: "",
                category = leg.category ?: "",
                trainNumber = leg.trainNumber,
                operatorRef = null,
                delay = 0,
                platform = "",
                platformChanged = false,
                routeDestination = routeDestination,
            )
        )
    }

    // Shared tracking entry: from a real board tap or a synthesised shared-route
    // leg. Everything downstream (timer cadence, watch/Garmin mirror, formation)
    // is identical once we have a FocusedDeparture. mirror=false when following
    // a track the watch already owns — re-sending it would make the watch
    // re-enter (and re-vibrate) its own tracking.
    private fun beginTracking(focused: FocusedDeparture, mirror: Boolean = true) {
        focusedTrain = focused
        appState = 2
        location.setTrackingAccuracy(true)
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = 0
        formation = null

        // Fetch formation for rail departures
        val trainNumber = focused.trainNumber
        val stationId = currentStation?.id
        if (trainNumber != null && Formation.isRailCategory(focused.category) && stationId != null) {
            val date = formationDateString()
            viewModelScope.launch {
                formation = runCatching {
                    api.fetchFormation(trainNumber, date, stationId, focused.operatorRef)
                }.getOrNull()
            }
        }

        startTimer(Timing.TRACKING_REFRESH_INTERVAL)
        haptics.shortPulse()

        // Foreground service + ongoing notification: the session survives (and
        // stays visible) when the app backgrounds. Without POST_NOTIFICATIONS
        // (API 33+) the system drops the notification silently, so ask now.
        trackingStartedTs = nowSeconds()
        TrackingNotificationService.start(getApplication(), buildTrackingSnapshot(focused))
        notificationPermissionRequest = true
        maybeShowBatteryNotice()

        // Mirror the same focused train onto the watch (immediate, a tap is a
        // strong, deliberate action). Keeps the manual "Send to Watch" too.
        if (mirror) {
            val trackCmd = TrackCommand.from(focused, stationId)
            mirrorToGarmin(trackCmd.toGarminMap())
            if (canMessageWear()) viewModelScope.launch { wearSync.sendTrack(trackCmd) }
        }
    }

    // ---- Tracking notification feed ----

    private var trackingStartedTs = 0L
    private var lastNotifKey: List<Any?> = emptyList()
    private var lastNotifPush = 0L

    private fun buildTrackingSnapshot(focused: FocusedDeparture): TrackingSnapshot {
        val gpsOk = gpsQuality != GpsQuality.UNAVAILABLE && gpsQuality != GpsQuality.LAST_KNOWN
        return TrackingSnapshot(
            focused = focused,
            stationId = currentStation?.id,
            stationName = currentStation?.name,
            stationLat = currentStation?.lat,
            stationLon = currentStation?.lon,
            walkDistMeters = if (gpsOk) lastWalkDist else null,
            gpsOk = gpsOk,
            startedEpochSeconds = trackingStartedTs,
        )
    }

    // Feed the notification from the in-app state. Called every tracking tick,
    // so it dedupes: only a material change (or 30 s of silence, keeping the
    // Live Update chip's countdown honest) re-renders.
    private fun pushTrackingNotification() {
        if (appState != 2) return
        val focused = focusedTrain ?: return
        val snap = buildTrackingSnapshot(focused)
        val walkMin = snap.walkDistMeters?.let { GeoUtils.walkMinutes(it).toInt() }
        val key = listOf(
            focused.delay, focused.platform, focused.destination, walkMin,
            TrackingLogic.status(
                TrackingLogic.effectiveBuffer(focused, walkMin?.toDouble() ?: 0.0, nowSeconds()),
                snap.gpsOk,
            ),
        )
        if (key == lastNotifKey && now() - lastNotifPush < 30_000) return
        lastNotifKey = key
        lastNotifPush = now()
        TrackingSessionBus.vmPush.tryEmit(snap)
    }

    // The service's first startForeground ran before the grant, so its
    // notification was dropped; re-post it the moment permission arrives.
    fun onNotificationPermissionResult(granted: Boolean) {
        if (granted && appState == 2) {
            lastNotifKey = emptyList()
            lastNotifPush = 0
            pushTrackingNotification()
        }
    }

    fun enterInactiveState() {
        onTrackingEnded(if (appState == 2) focusedTrain?.departureTimestamp else null)
        if (appState == 2) TrackingNotificationService.stop(getApplication())
        appState = 3
        location.setTrackingAccuracy(false)
        focusedTrain = null
        formation = null
        consecutiveErrors = 0
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
    }

    fun resumeFromInactive() {
        lastInteractionTime = now()
        appState = 0
    }

    // The Paused-screen resume button. Unlike the wake-helper resumeFromInactive
    // (called right before a launch), this is a terminal user action, so it can
    // safely re-search: a shared route that timed out into inactive returns to
    // the user's real location instead of the remote origin board.
    fun resumeToStationView() {
        resumeFromInactive()
        returnToNearbyIfLaunched()
    }

    fun updateDefaultMode(mode: TransportMode) {
        defaultMode = mode
        viewModelScope.launch { prefs.setDefaultMode(mode) }
    }

    fun updateAppearanceMode(mode: String) {
        viewModelScope.launch { prefs.setAppearanceMode(mode) }
    }

    // Companion to AppCompatDelegate.setApplicationLocales: the widget and
    // notification processes read this copy, then the widget re-renders.
    fun updateAppLanguage(tag: String) {
        viewModelScope.launch {
            prefs.setAppLanguage(tag)
            com.evanjt.traintime.widget.TrainTimeWidget().updateAll(getApplication())
        }
    }

    fun setRouteReminderLead(minutes: Int) {
        viewModelScope.launch { prefs.setRouteReminderLeadMinutes(minutes) }
    }

    fun setConnectionReminderLead(minutes: Int) {
        viewModelScope.launch { prefs.setConnectionReminderLeadMinutes(minutes) }
    }

    // One-shot flag: MainActivity launches the ACCESS_BACKGROUND_LOCATION request
    // when the user opts into background distance tracking without the grant.
    var backgroundLocationRequest by mutableStateOf(false)
        private set

    fun clearBackgroundLocationRequest() {
        backgroundLocationRequest = false
    }

    // One-shot introduction of the optional background-location feature, shown
    // once per install after the tour, only while the grant is missing. Declining
    // changes nothing: reminders keep using the last known location.
    var bgLocationIntro by mutableStateOf(false)
        private set
    private var bgLocationIntroAsk = false

    private fun maybeShowBgLocationIntro() {
        viewModelScope.launch {
            if (!prefs.bgLocationIntroSeen.first() &&
                !RouteDistanceTracker.hasBackgroundLocation(getApplication())
            ) {
                bgLocationIntro = true
            }
        }
    }

    fun acceptBgLocationIntro() {
        bgLocationIntro = false
        bgLocationIntroAsk = true
        viewModelScope.launch { prefs.markBgLocationIntroSeen() }
    }

    fun dismissBgLocationIntro() {
        bgLocationIntro = false
        viewModelScope.launch { prefs.markBgLocationIntroSeen() }
    }

    // The route sheet's "Enable background location" link: rerun the normal
    // disclosure + system flow (on Android 11+ the system opens the app's
    // location settings screen, where "Allow all the time" lives).
    fun enableBackgroundLocation() {
        backgroundLocationRequest = true
    }

    fun hasBackgroundLocation(): Boolean =
        RouteDistanceTracker.hasBackgroundLocation(getApplication())

    // Set when the user continued past the disclosure but declined "all the time".
    // Not a failure: the route is saved and the reminder still fires from the last
    // known location. Drives a reassuring dialog with a retry path. The upfront
    // intro skips it: declining an optional offer needs no follow-up.
    var backgroundLocationDenied by mutableStateOf(false)
        private set

    fun onBackgroundLocationResult(granted: Boolean) {
        backgroundLocationDenied = !granted && !bgLocationIntroAsk
        bgLocationIntroAsk = false
        syncReminderTracking()
    }

    // Battery-optimisation heads-up. Aggressive OEMs (OnePlus, Xiaomi, Samsung
    // and friends) kill the tracking foreground service once the app is
    // backgrounded unless it's exempted, so the notification silently vanishes.
    // Shown once, only on those OEMs and only while not yet exempted; Pixel/
    // stock and already-exempted users never see it.
    var batteryNotice by mutableStateOf(false)
        private set

    private fun maybeShowBatteryNotice() {
        viewModelScope.launch {
            if (!prefs.batteryNoticeSeen.first() && batteryKillsBackground()) {
                batteryNotice = true
            }
        }
    }

    fun dismissBatteryNotice() {
        batteryNotice = false
        viewModelScope.launch { prefs.markBatteryNoticeSeen() }
    }

    private fun batteryKillsBackground(): Boolean {
        if (Build.MANUFACTURER.lowercase() !in AGGRESSIVE_OEMS) return false
        val app = getApplication<Application>()
        // Defer past the first-run notification prompt so two dialogs never
        // stack; the notice can wait for a later tracking session.
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val pm = app.getSystemService(PowerManager::class.java) ?: return false
        return !pm.isIgnoringBatteryOptimizations(app.packageName)
    }

    fun clearBackgroundLocationDenied() {
        backgroundLocationDenied = false
    }

    fun setDistanceAwareReminder(value: Boolean) {
        viewModelScope.launch {
            prefs.setDistanceAwareReminder(value)
            if (value && prefs.backgroundReminderTracking.first()) maybeRequestBackgroundLocation()
            syncReminderTracking()
        }
    }

    fun setAlertBeforeDeparture(value: Boolean) {
        viewModelScope.launch { prefs.setAlertBeforeDeparture(value) }
    }

    fun setBackgroundReminderTracking(value: Boolean) {
        viewModelScope.launch {
            prefs.setBackgroundReminderTracking(value)
            if (value) maybeRequestBackgroundLocation()
            syncReminderTracking()
        }
    }

    private fun maybeRequestBackgroundLocation() {
        if (!RouteDistanceTracker.hasBackgroundLocation(getApplication())) {
            backgroundLocationRequest = true
        }
    }

    // Absolute epoch-second the reminder will fire for the active route, for the
    // green "notified in X min" line on the pending-route chip. Null when none.
    var reminderNotifyTs by mutableStateOf<Long?>(null)
        private set

    // The reminder split into walk + buffer for the chip's coloured readout.
    var reminderPlan by mutableStateOf<NotifyPlan?>(null)
        private set

    // Start/stop background distance tracking to match the current settings and
    // whether a route is active, and refresh the in-app notify countdown. Called
    // from the toggles, foreground, and route save/clear.
    private fun syncReminderTracking() {
        viewModelScope.launch {
            val ctx = getApplication<Application>()
            val route = pendingRouteStore.current()
            val plan = route?.let { PendingRouteNotifier.nextNotifyPlan(ctx, it) }
            reminderPlan = plan
            reminderNotifyTs = plan?.notifyTs
            val active = route != null &&
                prefs.distanceAwareReminder.first() &&
                prefs.backgroundReminderTracking.first() &&
                RouteDistanceTracker.hasBackgroundLocation(ctx)
            if (active) RouteDistanceTracker.start(ctx) else RouteDistanceTracker.stop(ctx)
        }
    }

    // Fires an immediate reminder so the user can confirm permission + delivery.
    fun sendTestNotification() {
        PendingRouteNotifier.sendTest(getApplication())
    }

    // Distance-aware test: computes the real distance from the current location
    // to the active route's origin (or the nearest station) and reports the lead
    // it would produce, immediately. Exercises the whole distance pipeline.
    fun sendDistanceReminderTest() {
        viewModelScope.launch {
            val ctx = getApplication<Application>()
            val coord = location.coordinate.value
            val leg = pendingRouteStore.current()?.currentLeg
            val originLat = leg?.originLat ?: currentStation?.lat
            val originLon = leg?.originLon ?: currentStation?.lon
            val originName = leg?.originName ?: currentStation?.name
            if (coord == null || originLat == null || originLon == null || originName == null) {
                PendingRouteNotifier.notifyNow(
                    ctx,
                    str(R.string.distance_test_title),
                    str(R.string.distance_test_need_loc),
                )
                return@launch
            }
            val dist = GeoUtils.haversineDistance(coord.lat, coord.lon, originLat, originLon)
            val walkMin = GeoUtils.walkMinutes(dist).toInt()
            val savedLeadSec = prefs.routeReminderLeadMinutes.first() * 60L
            val walkSec = (GeoUtils.walkMinutes(dist) * 60).toLong()
            val leadMin = (minOf(walkSec + savedLeadSec, PendingRouteLogic.MAX_LEAD_SEC) / 60).toInt()
            PendingRouteNotifier.notifyNow(
                ctx,
                str(R.string.distance_test_title_fmt, originName),
                str(R.string.distance_test_body_fmt, dist.toInt(), walkMin, leadMin),
            )
        }
    }

    fun markOnboardingSeen() {
        viewModelScope.launch { prefs.setSeenOnboardingVersion(CURRENT_TOUR_VERSION) }
    }

    fun replayOnboarding() {
        viewModelScope.launch { prefs.markOnboardingUnseen() }
    }

    // Only a real board tap counts toward the review ask: shared-route and
    // protected tracks skip it, matching iOS. Counting at the tap call site
    // (not the state-2 transition) means configuration changes can't recount.
    private fun maybeRequestReview() {
        viewModelScope.launch {
            prefs.incrementReviewTrackCount()
            val shouldPrompt = ReviewGate.shouldPrompt(
                trackCount = prefs.reviewTrackCount.first(),
                promptedVersion = prefs.reviewPromptedVersion.first(),
                currentVersion = BuildConfig.VERSION_NAME,
                firstLaunchTs = prefs.firstLaunchTs.first(),
                snoozeUntil = prefs.reviewSnoozeUntil.first(),
                optedOut = prefs.reviewOptOut.first(),
                now = System.currentTimeMillis(),
            )
            if (shouldPrompt) {
                // Shown counts as asked for this version, whatever button follows.
                prefs.setReviewPromptedVersion(BuildConfig.VERSION_NAME)
                showReviewPrompt = true
            }
        }
    }

    fun dismissReviewPrompt() {
        showReviewPrompt = false
    }

    fun snoozeReview() {
        viewModelScope.launch {
            prefs.setReviewSnoozeUntil(System.currentTimeMillis() + ReviewGate.SNOOZE_MS)
        }
    }

    fun optOutReview() {
        viewModelScope.launch { prefs.setReviewOptOut(true) }
    }

    fun toggleFavourite() {
        val focused = focusedTrain ?: return
        toggleFavourite(focused.lineNumber, focused.destination)
    }

    fun toggleFavouriteDeparture(departure: Departure) {
        toggleFavourite(departure.lineNumber, departure.destination)
    }

    private fun toggleFavourite(lineNumber: String, destination: String) {
        val station = currentStation ?: return
        lastInteractionTime = now() // curating favourites shouldn't trip the inactivity timeout
        viewModelScope.launch {
            favouritesStore.toggle(
                stationId = station.id,
                stationName = station.name ?: str(CoreR.string.station_fallback),
                lineNumber = lineNumber,
                destination = destination,
            )
        }
        haptics.shortPulse()
    }

    val isFocusedTrainFavourite: Boolean
        get() {
            val focused = focusedTrain ?: return false
            val stationId = currentStation?.id ?: return false
            return favouritesList.any {
                it.stationId == stationId &&
                    it.lineNumber == focused.lineNumber &&
                    it.destination == focused.destination
            }
        }

    fun isDepartureFavourite(departure: Departure): Boolean {
        val stationId = currentStation?.id ?: return false
        return favouritesList.any {
            it.stationId == stationId &&
                it.lineNumber == departure.lineNumber &&
                it.destination == departure.destination
        }
    }

    fun removeFavourite(favourite: Favourite) {
        viewModelScope.launch { favouritesStore.remove(favourite) }
    }

    // Send to Watch (mirrors iOS PhoneViewModel.sendToWatch). Wear OS is delivered over
    // the Wearable Data Layer; Garmin over the Connect IQ Mobile SDK.
    fun refreshConnectedWatches() {
        viewModelScope.launch { connectedWatches = currentConnectedWatches() }
    }

    // For the Settings link-status display: paired watches and whether each is reachable.
    fun refreshWatchLinks() {
        viewModelScope.launch {
            val wearNames = wearSync.connectedWatchNames()
            noteWearNodes(wearNames)
            val wear = wearNames.map { WatchLink(it, PhoneWatchType.WEAR, true) }
            // eligibleDevices are connected + have TrainTime installed, so all are reachable.
            val garmin = garminService.eligibleDevices()
            garminTargetIds = garmin.map { it.id }
            watchLinks = wear + buildGarminLinks(garmin)
            updateKnownButDisconnected()
            persistGarminEverConnected()
        }
    }

    // Latch "a Garmin has actually connected here" for the reminder worker, which
    // can't sweep the Connect IQ SDK from its background window. Sticky and set
    // only from an eligible (connected + app-installed) device, so the "Send to
    // Watch" action never appears for someone who has never connected a Garmin.
    private suspend fun persistGarminEverConnected() {
        if (garminTargetIds.isNotEmpty()) prefs.markGarminEverConnected()
    }

    fun setMirrorToWatch(value: Boolean) {
        viewModelScope.launch { prefs.setMirrorToWatch(value) }
    }

    // Push an action payload to every eligible Garmin watch when mirroring is on.
    // Optional overlay: off, or no watch → no-op. Fire-and-forget, never blocks.
    private fun mirrorToGarmin(payload: Map<String, Any?>) {
        if (!canMessageWatch()) return
        viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
    }

    // True only when we may send to the watch: mirroring on, a target exists, and the
    // watch app is actually open. The last guard is what stops the phone from waking a
    // closed watch-app. One per backend.
    private fun canMessageWatch(): Boolean = mirrorToWatch && garminTargetIds.isNotEmpty() && garminAliveFresh()
    private fun canMessageWear(): Boolean = mirrorToWatch && wearNodesPresent && wearAliveFresh()

    // Wear peers of mirrorToGarmin / mirrorToGarminDebounced, over CMD_PATH.
    private fun mirrorToWear(cmd: WearCommand) {
        if (!canMessageWear()) return
        viewModelScope.launch { wearSync.sendCommand(cmd) }
    }

    private fun mirrorToWearDebounced(cmd: () -> WearCommand) {
        if (!canMessageWear()) return
        wearMirrorJob?.cancel()
        wearMirrorJob = viewModelScope.launch {
            delay(300)
            wearSync.sendCommand(cmd())
        }
    }

    // Bring a freshly-announced Wear watch in line with the phone: the tracked
    // train if we're tracking, otherwise the current station, plus the location.
    private fun syncCurrentStateToWear() {
        if (!canMessageWear()) return
        location.coordinate.value?.let { c ->
            mirrorToWear(WearCommand("loc", lat = c.lat, lon = c.lon))
        }
        val focused = focusedTrain
        if (appState == 2 && focused != null) {
            val cmd = TrackCommand.from(focused, currentStation?.id)
            viewModelScope.launch { wearSync.sendTrack(cmd) }
        } else {
            currentStation?.let { st ->
                mirrorToWear(WearCommand("station", stId = st.id, name = st.name ?: str(CoreR.string.station_fallback), lat = st.lat, lon = st.lon))
            }
        }
    }

    // Reply to a Wear watch's explicit reqLoc with the phone's current coordinate.
    private fun replyWithLocationToWear() {
        if (location.loadedFromCache) return
        if (!mirrorToWatch || !wearNodesPresent) return
        val coord = location.coordinate.value ?: return
        viewModelScope.launch { wearSync.sendCommand(WearCommand("loc", lat = coord.lat, lon = coord.lon)) }
    }

    // Debounced variant for rapid changes (mode cycling, station scrolling), the
    // latest settled state wins, so the BLE channel isn't flooded.
    private fun mirrorToGarminDebounced(payload: () -> Map<String, Any?>) {
        if (!canMessageWatch()) return
        mirrorJob?.cancel()
        mirrorJob = viewModelScope.launch {
            delay(300)
            val p = payload()
            garminTargetIds.forEach { garminService.send(it, p) }
        }
    }

    // Proactive location backfill: when mirroring, push the phone's coordinate to
    // the watch so it has a fallback for weak GPS. Debounced ≥10 s / ≥100 m so a
    // settled phone (or a mock-GPS app) keeps the watch fed without flooding.
    private fun maybePushLocationToWatch(coord: LatLon) {
        // A cached coordinate may be from another city; relaying it hands the
        // watch a confident-looking fix with zero proof behind it.
        if (location.loadedFromCache) return
        val garminOk = canMessageWatch()
        val wearOk = canMessageWear()
        if (!garminOk && !wearOk) return
        val last = lastPushedLoc
        val movedEnough = last == null ||
            GeoUtils.haversineDistance(last.lat, last.lon, coord.lat, coord.lon) >= 100.0
        if (!movedEnough && now() - lastLocPushTime < 10_000) return
        lastPushedLoc = coord
        lastLocPushTime = now()
        if (garminOk) {
            val payload = WearSync.garminLocationPayload(coord.lat, coord.lon)
            viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
        }
        if (wearOk) mirrorToWear(WearCommand("loc", lat = coord.lat, lon = coord.lon))
    }

    // Force-push the current location to all eligible watches, bypassing the
    // movement/time debounce. Used on app open and when opening the watch app.
    private fun pushLocationNow() {
        if (location.loadedFromCache) return
        val garminOk = canMessageWatch()
        val wearOk = canMessageWear()
        if (!garminOk && !wearOk) return
        val coord = location.coordinate.value ?: return
        lastPushedLoc = coord
        lastLocPushTime = now()
        if (garminOk) {
            val payload = WearSync.garminLocationPayload(coord.lat, coord.lon)
            viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
        }
        if (wearOk) mirrorToWear(WearCommand("loc", lat = coord.lat, lon = coord.lon))
    }

    // Bring a freshly-opened watch in line with the phone: the tracked train if we're
    // tracking, otherwise the current station, plus the current location. This is what
    // makes the watch button (header or tracking screen) open the watch onto the same view.
    private fun syncCurrentStateToWatch() {
        if (!canMessageWatch()) return
        val focused = focusedTrain
        val payload = if (appState == 2 && focused != null) {
            TrackCommand.from(focused, currentStation?.id).toGarminMap()
        } else {
            currentStation?.let { st ->
                WearSync.garminStationPayload(st.id, st.name ?: str(CoreR.string.station_fallback), st.lat, st.lon)
            }
        }
        // View payload first: when the user is waiting on a countdown, the track
        // command must not queue behind a location push and a favourites blob.
        if (payload != null) {
            viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
        }
        pushLocationNow()
        // Re-seed favourites so a freshly-opened watch unions in anything it lacks.
        pushFavouritesToGarmin(favouritesList)
    }

    // The pending-track path: the tracked departure goes out first, then the
    // location/favourites seeding, then one delayed resend unless the watch's
    // trackStarted echo already confirmed it landed (a send can race the watch's
    // cold start and vanish — the silent "it just didn't track" failure).
    private fun sendFocusedTrackFirst() {
        val focused = focusedTrain
        if (appState != 2 || focused == null) {
            syncCurrentStateToWatch()
            return
        }
        val payload = TrackCommand.from(focused, currentStation?.id).toGarminMap()
        viewModelScope.launch {
            garminTargetIds.forEach { garminService.send(it, payload) }
            pushLocationNow()
            pushFavouritesToGarmin(favouritesList)
            delay(2_000)
            if (!watchTrackingFocused) {
                garminTargetIds.forEach { garminService.send(it, payload) }
            }
        }
    }

    // Reply to a watch's explicit reqLoc with the phone's current coordinate.
    private fun replyWithLocation() {
        if (location.loadedFromCache) return
        if (!mirrorToWatch || garminTargetIds.isEmpty()) return
        val coord = location.coordinate.value ?: return
        val payload = WearSync.garminLocationPayload(coord.lat, coord.lon)
        viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
    }

    private suspend fun currentConnectedWatches(): List<ConnectedWatch> {
        // Only watches that actually have the Wear app installed, so we never
        // offer to send a departure to a paired watch that can't receive it.
        val wear = wearSync.appInstalledWatchNames().mapIndexed { i, name ->
            ConnectedWatch("wear_$i", name, PhoneWatchType.WEAR)
        }
        val garmin = garminService.eligibleDevices().map { d ->
            ConnectedWatch("garmin_${d.id}", d.name, PhoneWatchType.GARMIN)
        }
        return wear + garmin
    }

    // Single connected watch: send straight to it. Multiple: the UI calls this per target.
    fun sendToWatch(target: ConnectedWatch? = null) {
        val focused = focusedTrain ?: return
        val stationId = currentStation?.id
        viewModelScope.launch {
            val watches = currentConnectedWatches()
            connectedWatches = watches
            val watch = target ?: watches.singleOrNull()
            if (watch == null) {
                showWatchStatus(str(R.string.no_watch_connected))
                return@launch
            }
            // Guard: the sync features require a watch reporting 0.5.x or higher.
            // A watch below that, or one we have heard no version from, is asked
            // to update rather than shown a false "Sent".
            val version = when (watch.type) {
                PhoneWatchType.WEAR -> wearWatchVersion
                PhoneWatchType.GARMIN -> garminWatchVersion
            }
            if (!WearSync.meetsSyncMinimum(version)) {
                showWatchStatus(str(R.string.update_watch_fmt, version ?: WearSync.LEGACY_VERSION_NAME))
                return@launch
            }
            val cmd = TrackCommand.from(focused, stationId)
            val garminDeviceId = watch.id.removePrefix("garmin_")
            val ok = when (watch.type) {
                PhoneWatchType.WEAR -> wearSync.sendTrack(cmd) > 0
                PhoneWatchType.GARMIN -> garminService.sendTrack(garminDeviceId, cmd.toGarminMap())
            }
            showWatchStatus(if (ok) str(R.string.sent_to_fmt, watch.name) else str(R.string.failed_to_send))

            // SDK SUCCESS means "delivered to the device", not "the app saw it".
            // On a pv>=3 watch the trackStarted echo is the real ack; no echo
            // means the app was probably closed behind a stale alive reading, so
            // relaunch it with the track queued instead of leaving a false "Sent".
            if (ok && watch.type == PhoneWatchType.GARMIN && garminWatchPv >= 3) {
                delay(4_000)
                if (!watchTrackingFocused && appState == 2 && focusedTrain == focused) {
                    pendingWatchTrackSend = true
                    watchChecking = true
                    showWatchStatus(str(R.string.watch_not_responding))
                    garminService.openApp(garminDeviceId)
                    delay(8_000)
                    if (watchChecking) {
                        watchChecking = false
                        recomputeWatchAlive()
                    }
                }
            }
        }
    }

    // Tracking-screen watch button: a live watch takes an explicit send; a closed
    // Garmin takes the launch/re-sync path (a closed Garmin app must be opened
    // before it can receive). Mirrors iOS PhoneViewModel.sendToPrimaryOrOpen. The
    // UI routes multiple watches through the picker instead.
    fun sendToPrimaryOrOpen() {
        viewModelScope.launch {
            connectedWatches = currentConnectedWatches()
            val hasGarminLink = watchLinks.any { it.type == PhoneWatchType.GARMIN }
            if (!watchAlive && hasGarminLink) {
                // Launch path: remember the intent so the hello answers with the
                // track command first, not the generic state sync.
                pendingWatchTrackSend = appState == 2 && focusedTrain != null
                openWatchApp()
            } else {
                sendToWatch()
            }
        }
    }

    // Applies a state sync pushed from a watch (defaultMode). Garmin sends this via the
    // Connect IQ message channel; Wear arrives through the listener service / DataClient.
    private fun applyReceivedWatchContext(ctx: Map<String, Any?>) {
        // Any message but bye proves the watch app is open, not just the explicit
        // liveness kinds: a saveReminder or favourites push greens the indicator
        // and unblocks the alive-gated sends (e.g. the reminder ack).
        val wasAlive = garminAliveFresh()
        if (ctx["kind"] != "bye") {
            garminLastAlive = now()
            garminLastAliveHighWater = garminLastAlive
            recomputeWatchAlive()
        }
        // Liveness announcement, the watch app is open and reachable (hello on launch,
        // alive as its periodic heartbeat).
        if (ctx["kind"] == "hello" || ctx["kind"] == "alive") {
            // A pre-versioning Garmin build sends no version: read as 0.4.x.
            garminWatchVersion = ctx["v"] as? String ?: WearSync.LEGACY_VERSION_NAME
            garminWatchPv = (ctx["pv"] as? Number)?.toInt() ?: 0
            watchAlive = true
            watchChecking = false
            // pv>=3 heartbeats carry the tracked departure; their absence on
            // such a watch means "not tracking". Older watches stay edge-driven
            // (trackStarted only), so silence doesn't clear them here.
            val trk = (ctx["trk"] as? Number)?.toLong()
            if (trk != null) {
                if ((watchTrackingInfo?.get("depTs") as? Number)?.toLong() != trk) watchTrackingInfo = null
                watchTrackingDepTs = trk
                watchTrackingLine = ctx["trkLn"] as? String
                watchTrackingSource = PhoneWatchType.GARMIN
            } else if (garminWatchPv >= 3 && watchTrackingSource == PhoneWatchType.GARMIN) {
                clearWatchTracking()
            }
            // A user-initiated track send takes priority and goes out first —
            // it's the time-critical payload. Otherwise a freshly-online watch
            // jumps to whatever the phone is showing (tracking train, or current
            // station) and gets seeded with the phone's location.
            if (pendingWatchTrackSend) {
                pendingWatchTrackSend = false
                sendFocusedTrackFirst()
            } else if (!wasAlive) {
                syncCurrentStateToWatch()
            }
            return
        }
        // The watch entered tracking (its own tap, or the echo of our track
        // command — the echo doubles as the delivery ack).
        if (ctx["kind"] == "trackStarted") {
            watchTrackingDepTs = (ctx["depTs"] as? Number)?.toLong()
            watchTrackingLine = ctx["line"] as? String
            watchTrackingInfo = ctx
            watchTrackingSource = PhoneWatchType.GARMIN
            return
        }
        if (ctx["kind"] == "trackEnded") {
            if (watchTrackingSource != PhoneWatchType.WEAR) clearWatchTracking()
            return
        }
        // The watch app is closing, flip the indicator straight away. The high
        // water mark stays: bye after alive is exactly what the ping gate reads.
        if (ctx["kind"] == "bye") {
            garminLastAlive = 0L
            garminLastBye = now()
            recomputeWatchAlive()
            watchChecking = false
            if (watchTrackingSource != PhoneWatchType.WEAR) clearWatchTracking()
            viewModelScope.launch { persistGarminLinkState() }
            return
        }
        // The watch is asking for the phone's location (its own GPS is weak).
        if (ctx["kind"] == "reqLoc") {
            replyWithLocation()
            return
        }
        // The watch (Garmin) asked us to save its focused departure as a reminder.
        if (ctx["kind"] == "saveReminder") {
            saveReminderFromWatch(ctx)
            return
        }
        // The Garmin watch pushed its favourites: outer-join them into ours.
        if (ctx["kind"] == "favourites") {
            applyGarminFavourites(ctx["favs"])
            return
        }
        val modeRaw = (ctx["defaultMode"] as? Number)?.toInt() ?: return
        viewModelScope.launch { prefs.setDefaultMode(TransportMode.fromRaw(modeRaw)) }
    }

    // Reconstruct the one-leg route the Garmin watch described and queue it for a
    // reminder (peer of the Apple saveReminderFromWatch and the Wear listener).
    // Numbers arrive as Java Number across the Connect IQ bridge.
    private fun saveReminderFromWatch(ctx: Map<String, Any?>) {
        val dest = ctx["dest"] as? String ?: return
        val depTs = (ctx["depTs"] as? Number)?.toLong() ?: return
        val line = ctx["line"] as? String ?: return
        val stId = ctx["stId"] as? String ?: return
        val lat = (ctx["lat"] as? Number)?.toDouble() ?: return
        val lon = (ctx["lon"] as? Number)?.toDouble() ?: return
        // Ack receipt (not save) as soon as the payload parses, so the watch can
        // clear its outbox: retries of the same id land here idempotently. An old
        // watch sends no id and expects no ack.
        (ctx["id"] as? String)?.let { ackReminderToGarmin(it) }
        val route = SharedRoute.single(
            originId = stId,
            originName = ctx["stName"] as? String ?: str(CoreR.string.station_fallback),
            originLat = lat,
            originLon = lon,
            destName = dest,
            depTs = depTs,
            lineNumber = line,
            trainNumber = ctx["trainNum"] as? String,
        )
        viewModelScope.launch {
            PendingRouteNotifier.saveAndSchedule(getApplication(), route, nowSeconds())
        }
    }

    private fun ackReminderToGarmin(id: String) {
        val payload = WearSync.garminAckReminderPayload(id)
        viewModelScope.launch {
            val ids = garminTargetIds.ifEmpty {
                garminService.eligibleDevices().map { it.id }.also { garminTargetIds = it }
            }
            ids.forEach { garminService.send(it, payload) }
        }
    }

    // Outer-join the Garmin watch's favourites into ours. The store change re-pushes
    // the merged set to every watch via the favourites observer; the Garmin watch
    // unions and never re-broadcasts, so this converges without a loop.
    private fun applyGarminFavourites(raw: Any?) {
        val incoming = (raw as? List<*>)?.mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val stId = m["stId"] as? String ?: return@mapNotNull null
            val line = m["line"] as? String ?: return@mapNotNull null
            val dest = m["dest"] as? String ?: return@mapNotNull null
            Favourite(stId, m["name"] as? String ?: stId, line, dest)
        } ?: return
        viewModelScope.launch {
            val current = favouritesStore.all()
            val merged = FavouritesStore.union(current, incoming)
            if (merged != current) favouritesStore.replaceAll(merged)
        }
    }

    // Push our favourites to every connected Garmin watch for the outer-join sync.
    private fun pushFavouritesToGarmin(favourites: List<Favourite>) {
        if (!canMessageWatch() || garminTargetIds.isEmpty()) return
        val payload = WearSync.garminFavouritesPayload(favourites)
        viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
    }

    override fun onCleared() {
        garminService.shutdown()
        super.onCleared()
    }

    private fun showWatchStatus(status: String) {
        watchSendStatus = status
        viewModelScope.launch {
            delay(2000)
            watchSendStatus = null
        }
    }

    fun exitToStationView() {
        val wasTracking = appState == 2
        onTrackingEnded(if (wasTracking) focusedTrain?.departureTimestamp else null)
        if (wasTracking) TrackingNotificationService.stop(getApplication())
        // A queued "track on watch" intent dies with the tracking session.
        pendingWatchTrackSend = false
        lastInteractionTime = now()
        appState = 0
        location.setTrackingAccuracy(false)
        focusedTrain = null
        formation = null
        consecutiveErrors = 0
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
        // A shared route launched a remote origin station, go back to the
        // nearby list at the user's real location rather than that origin.
        returnToNearbyIfLaunched()
        // Deliberately do NOT tell the watch to leave tracking. The watch tracks
        // independently, and tracking is the end game there, it must not be
        // interrupted by the phone going back. Selecting another departure sends
        // a fresh track command, which is the only thing that switches it.
    }

    // Mode navigation

    fun selectMode(mode: TransportMode) {
        lastInteractionTime = now()
        if (mode == currentMode) return
        currentMode = mode
        stationIndex = 0
        adoptEmbeddedOrFetch()
        mirrorToGarminDebounced { WearSync.garminModePayload(mode.raw) }
        mirrorToWearDebounced { WearCommand("mode", mode = mode.raw) }
    }

    fun selectStation(index: Int) {
        lastInteractionTime = now()
        if (index < 0 || index >= stations.size) return
        stationIndex = index
        showStationPicker = false
        adoptEmbeddedOrFetch()
        currentStation?.let { st ->
            mirrorToGarminDebounced { WearSync.garminStationPayload(st.id, st.name ?: str(CoreR.string.station_fallback), st.lat, st.lon) }
            mirrorToWearDebounced { WearCommand("station", stId = st.id, name = st.name ?: str(CoreR.string.station_fallback), lat = st.lat, lon = st.lon) }
        }
    }

    private fun adoptEmbeddedOrFetch() {
        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            viewModelScope.launch { favouriteDepartures = extractFavouritesFromCurrent(deps) }
            lastFetchTime = now()
        } else {
            // Keep the previous list visible (greyed via departuresRefreshing)
            // until the new board arrives, rather than blanking to a spinner.
            currentStation?.let { fetchDepartures(it.id) }
        }
    }

    // Pinned "My stations"

    fun isStationPinned(id: String): Boolean = id in pinnedStationIds

    fun togglePinnedStation(station: Station) {
        lastInteractionTime = now()
        viewModelScope.launch { myStationsStore.toggle(station) }
    }

    // Re-sort the already-loaded mode lists so pinned stations sit at the front,
    // keeping the currently-shown station selected (pinning is a default, it
    // doesn't yank the user off the station they're looking at).
    private fun applyPinnedReorder() {
        if (trainStations.isEmpty() && busStations.isEmpty() &&
            tramStations.isEmpty() && specialStations.isEmpty()
        ) {
            return
        }
        val selectedId = currentStation?.id
        trainStations = MyStationsStore.reorder(trainStations, pinnedStationIds)
        busStations = MyStationsStore.reorder(busStations, pinnedStationIds)
        tramStations = MyStationsStore.reorder(tramStations, pinnedStationIds)
        specialStations = MyStationsStore.reorder(specialStations, pinnedStationIds)
        selectedId?.let { id -> locate(id)?.let { (m, i) -> currentMode = m; stationIndex = i } }
    }

    // Find a station by id across all mode arrays.
    private fun locate(stationId: String): Pair<TransportMode, Int>? {
        val groups = listOf(
            TransportMode.TRAIN to trainStations,
            TransportMode.BUS to busStations,
            TransportMode.TRAM to tramStations,
            TransportMode.SPECIAL to specialStations,
        )
        for ((mode, list) in groups) {
            val idx = list.indexOfFirst { it.id == stationId }
            if (idx >= 0) return mode to idx
        }
        return null
    }

    // Rebuild the mode list after a station fetch. When preserveStationId still
    // exists in the new results, keep the user on that station/mode (in-place
    // refresh); otherwise select the nearest.
    private fun rebuildModesAndSelect(preserveStationId: String? = null) {
        val modes = buildList {
            if (trainStations.isNotEmpty()) add(TransportMode.TRAIN)
            if (busStations.isNotEmpty()) add(TransportMode.BUS)
            if (tramStations.isNotEmpty()) add(TransportMode.TRAM)
            if (specialStations.isNotEmpty()) add(TransportMode.SPECIAL)
        }
        availableModes = modes

        var preserved = false
        val located = preserveStationId?.let { locate(it) }
        if (located != null) {
            currentMode = located.first
            stationIndex = located.second
            preserved = true
        } else {
            if (stations.isEmpty()) {
                if (modes.contains(defaultMode)) {
                    currentMode = defaultMode
                } else {
                    modes.firstOrNull()?.let { currentMode = it }
                }
            }
            stationIndex = 0
        }

        // Adopt fresh embedded departures if present. On the non-preserved path,
        // blank and refetch. On the preserved path with no fresh embedded
        // departures, leave the existing list untouched (no flash).
        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            viewModelScope.launch { favouriteDepartures = extractFavouritesFromCurrent(deps) }
            lastFetchTime = now()
        } else if (!preserved) {
            departures = emptyList()
            favouriteDepartures = emptyList()
            currentStation?.let { fetchDepartures(it.id) }
        }

        // Handle pending deep link after stations load
        pendingDeepLink?.let {
            pendingDeepLink = null
            handleDeepLink(it)
        }
    }

    // Focused train update

    private fun updateFocusedTrain() {
        val focused = focusedTrain ?: return
        val nowS = nowSeconds()

        // Matching + adoption live in TrackingLogic, shared with the background
        // service's loop so both paths track the same train the same way.
        val best = TrackingLogic.matchFocused(departures, focused, nowS)
        if (best == null) {
            // A still-future train just isn't on the board yet (a shared route
            // opened early, before it reaches the 20-row horizon). Keep the
            // local countdown; only give up once it has actually departed.
            if (nowS < focused.departureTimestamp + PendingRouteLogic.GRACE_SEC) return
            haptics.shortPulse()
            exitToStationView()
            return
        }

        if (best.platform != focused.platform && best.platform.isNotEmpty() && best.platformChanged) {
            haptics.doublePulse()
        }
        focusedTrain = TrackingLogic.adopt(focused, best)
        pushTrackingNotification()
    }

    // Tracking calculations

    val trackingScheduledBuffer: Double
        get() {
            val focused = focusedTrain ?: return 0.0
            val walkMin = lastWalkTime?.let { it / 60.0 } ?: GeoUtils.walkMinutes(lastWalkDist)
            return focused.minutesUntil(nowSeconds()) - walkMin
        }

    val trackingEffectiveBuffer: Double
        get() {
            val focused = focusedTrain ?: return 0.0
            return trackingScheduledBuffer + focused.delay.toDouble()
        }

    val trackingStatusText: String
        get() {
            val buf = trackingEffectiveBuffer
            // A cached coordinate is zero proof of position: computing an
            // ahead/behind verdict from it produced the "800 min behind"
            // failure when the seed was a city away.
            if (gpsQuality == GpsQuality.UNAVAILABLE || gpsQuality == GpsQuality.LAST_KNOWN) return str(CoreR.string.no_gps)
            val absBuf = kotlin.math.abs(buf)
            if (absBuf < 0.5) return str(CoreR.string.on_time)
            val unit = if (absBuf < 1.5) str(CoreR.string.buf_sec_fmt, (absBuf * 60).toInt()) else str(CoreR.string.buf_min_fmt, absBuf.toInt())
            return if (buf > 0) str(CoreR.string.ahead_fmt, unit) else str(CoreR.string.behind_fmt, unit)
        }

    // Resolved to a palette colour in the composable so it follows light/dark.
    val trackingStatus: TrackingStatus
        get() {
            if (gpsQuality == GpsQuality.UNAVAILABLE || gpsQuality == GpsQuality.LAST_KNOWN) return TrackingStatus.NO_GPS
            val buf = trackingEffectiveBuffer
            return when {
                buf > 0.5 -> TrackingStatus.AHEAD
                buf < -0.5 -> TrackingStatus.BEHIND
                else -> TrackingStatus.ON_TIME
            }
        }

    val directionToStation: Double?
        get() {
            val userCoord = location.coordinate.value ?: return null
            val station = currentStation ?: return null
            val stationLat = station.lat ?: return null
            val stationLon = station.lon ?: return null
            val heading = location.heading ?: return null
            val bearing = GeoUtils.bearing(userCoord.lat, userCoord.lon, stationLat, stationLon)
            return Math.toDegrees(bearing - heading)
        }

    // While tracking a shared-route leg, every remaining ride leg of the same
    // route: the onward journey, each shown as its own row under the countdown
    // and tappable to jump onto it early. Change minutes are measured from the
    // previous ride leg's arrival. Empty for a plain (non-route) track.
    val onwardLegs: List<OnwardConnection>
        get() {
            val focused = focusedTrain ?: return emptyList()
            val route = pendingRoute ?: return emptyList()
            val curIdx = route.legs.indexOfFirst {
                it.type == LegType.RIDE && it.depTs == focused.departureTimestamp
            }
            if (curIdx < 0) return emptyList()
            val result = mutableListOf<OnwardConnection>()
            var prevRide = route.legs[curIdx]
            for (i in curIdx + 1 until route.legs.size) {
                val leg = route.legs[i]
                if (leg.type != LegType.RIDE) continue
                val changeMinutes = ((leg.depTs - prevRide.arrTs) / 60).coerceAtLeast(0)
                result += OnwardConnection(prevRide.destName, leg, i, changeMinutes)
                prevRide = leg
            }
            return result
        }

    // The immediate next connection, for surfaces that show only one.
    val onwardConnection: OnwardConnection?
        get() = onwardLegs.firstOrNull()

    // API calls

    private fun fetchStations(lat: Double, lon: Double) {
        if (requestInFlight) return
        // A real nearby search supersedes any launched remote station.
        launchedStationActive = false
        requestInFlight = true
        requestStartTime = now()

        viewModelScope.launch {
            try {
                val result = api.fetchStations(lat, lon, defaultMode)
                requestInFlight = false
                requestStartTime = null
                val prevStationId = currentStation?.id
                trainStations = MyStationsStore.reorder(result.train, pinnedStationIds)
                busStations = MyStationsStore.reorder(result.bus, pinnedStationIds)
                tramStations = MyStationsStore.reorder(result.tram, pinnedStationIds)
                specialStations = MyStationsStore.reorder(result.special, pinnedStationIds)
                lastSearchCoordinate = LatLon(lat, lon)
                location.saveLastKnownCoordinate()
                rebuildModesAndSelect(preserveStationId = prevStationId)

                if (stations.isEmpty()) {
                    status = str(CoreR.string.status_no_stations_nearby)
                    isOutOfBounds = false
                }
            } catch (e: Exception) {
                requestInFlight = false
                requestStartTime = null
                handleError(e, str(CoreR.string.ctx_stations))
            }
        }
    }

    // True while a departures fetch is in flight. The station screen dims the
    // existing list and shows a slim progress line instead of blanking to a
    // full-screen spinner, so a refresh freezes the list rather than hiding it.
    var departuresRefreshing by mutableStateOf(false)
        private set

    fun fetchDepartures(stationId: String) {
        viewModelScope.launch { fetchDeparturesAsync(stationId) }
    }

    private suspend fun fetchDeparturesAsync(stationId: String) {
        if (requestInFlight) return
        requestInFlight = true
        requestStartTime = now()
        departuresRefreshing = true

        try {
            val favParam = favouritesStore.favouritesParam(stationId)
            val result = api.fetchDepartures(stationId, favParam)
            requestInFlight = false
            requestStartTime = null
            departuresRefreshing = false
            lastFetchTime = now()
            consecutiveErrors = 0
            departures = if (result.favourites.isNotEmpty()) {
                FavouritesStore.merge(result.favourites, result.departures)
            } else {
                result.departures
            }
            favouriteDepartures = if (result.favourites.isNotEmpty()) {
                result.favourites
            } else {
                favouritesStore.extractFavourites(result.departures, stationId)
            }

            if (appState == 2) updateFocusedTrain()
            tryEnterPendingShareTrack()
        } catch (e: Exception) {
            requestInFlight = false
            requestStartTime = null
            departuresRefreshing = false
            // Offline or server error: the shared route must not be lost,
            // queue it; the resume flow re-checks the board later.
            pendingShareTrack?.let { offer ->
                pendingShareTrack = null
                saveOfferAsQueued(offer)
            }
            handleError(e, str(CoreR.string.ctx_departures))
        }
    }

    // Pull-to-refresh: bypasses the timer cooldown by fetching directly.
    suspend fun forceRefresh() {
        lastInteractionTime = now()
        var waited = 0
        while (requestInFlight && waited < 100) { // ride out an in-flight timer fetch (≤10s)
            delay(100)
            waited += 1
        }
        val id = currentStation?.id ?: return
        fetchDeparturesAsync(id)
    }

    // Error handling

    private fun handleError(error: Exception, context: String) {
        if (appState == 2) {
            // In tracking mode: keep existing data, continue countdown
            consecutiveErrors += 1
            return
        }

        status = when (error) {
            is TrainApiException.RateLimited -> str(CoreR.string.err_rate_limited)
            is TrainApiException.Http -> str(CoreR.string.err_code_fmt, context, error.code)
            is TrainApiException.NoData -> str(CoreR.string.err_generic_fmt, context)
            is TrainApiException.Network -> str(CoreR.string.err_no_connection)
            else -> str(CoreR.string.err_generic_fmt, context)
        }
        isOutOfBounds = false
        departures = emptyList()
        favouriteDepartures = emptyList()
    }

    // Formation

    private fun formationDateString(): String =
        LocalDate.now(ZoneId.of("Europe/Zurich")).toString()

    private suspend fun extractFavouritesFromCurrent(deps: List<Departure>): List<Departure> {
        val stationId = currentStation?.id ?: return emptyList()
        return favouritesStore.extractFavourites(deps, stationId)
    }

    // Widget cache

    // Seed the widget's shared snapshot with what the user last saw, with a fresh
    // fetchTime that re-arms the widget's active window. The selected station carries
    // the full fetched list; the rest carry whatever the nearby search embedded.
    private fun seedWidgetCache() {
        if (currentStation == null) return
        val snapshot = com.evanjt.traintime.widget.WidgetFetchResult(
            train = widgetStations(trainStations, TransportMode.TRAIN),
            bus = widgetStations(busStations, TransportMode.BUS),
            tram = widgetStations(tramStations, TransportMode.TRAM),
            special = widgetStations(specialStations, TransportMode.SPECIAL),
            selectedModeRaw = currentMode.raw,
            selectedStationIndex = stationIndex,
            fetchTime = nowSeconds(),
        )
        val context = getApplication<Application>().applicationContext
        viewModelScope.launch {
            com.evanjt.traintime.widget.WidgetStateDefinition.update(context) {
                it.copy(result = snapshot, refreshStartedAt = 0, dormant = false, outsideSwitzerland = false)
            }
            com.evanjt.traintime.widget.TrainTimeWidget().updateAll(context)
            com.evanjt.traintime.widget.work.WidgetRefresher.scheduleTick(context)
        }
    }

    private fun widgetStations(list: List<Station>, mode: TransportMode): List<com.evanjt.traintime.widget.WidgetStation> =
        list.mapNotNull { station ->
            val name = station.name ?: return@mapNotNull null
            val deps = if (mode == currentMode && station.id == currentStation?.id && departures.isNotEmpty()) {
                departures
            } else {
                station.embeddedDepartures ?: emptyList()
            }
            com.evanjt.traintime.widget.WidgetStation(
                id = station.id,
                name = name,
                departures = deps.map {
                    com.evanjt.traintime.widget.WidgetDeparture(
                        destination = it.destination,
                        departureTimestamp = it.departureTimestamp ?: 0,
                        delay = it.delay,
                        platform = it.platform,
                        platformChanged = it.platformChanged,
                        lineNumber = it.lineNumber,
                    )
                },
            )
        }

    // Deep link

    fun handleDeepLink(uri: Uri) {
        lastInteractionTime = now()
        if (uri.scheme != "traintime") return

        // traintime://sbbshare[?url=...]: wake the app; with a url param,
        // process it as shared text (adb-testable path for the share flow).
        if (uri.host == "sbbshare") {
            if (appState == 3) resumeFromInactive()
            uri.getQueryParameter("url")?.let { handleSharedText(it) }
            return
        }

        // traintime://resumeroute: reminder notification tap. Track the current
        // leg directly (no prompt); the chip covers the manual case.
        if (uri.host == "resumeroute") {
            if (appState == 3) resumeFromInactive()
            resumePendingRoute()
            return
        }

        // traintime://sendtowatch: reminder "Send to Watch" action. Opens the app
        // (Connect IQ only binds in the foreground) and pushes the route to Garmin.
        if (uri.host == "sendtowatch") {
            if (appState == 3) resumeFromInactive()
            sendPendingRouteToWatch()
            return
        }

        // traintime://track?destination=DEST&timestamp=TS
        if (uri.host != "track") return
        val destination = uri.getQueryParameter("destination") ?: return
        val timestamp = uri.getQueryParameter("timestamp")?.toLongOrNull() ?: return

        // If we don't have departures yet, save for later
        if (departures.isEmpty()) {
            pendingDeepLink = uri
            return
        }

        val index = departures.indexOfFirst {
            it.destination == destination && it.departureTimestamp == timestamp
        }
        if (index >= 0) selectDeparture(index)
    }

    // Shared SBB trip intake (share sheet / sbbshare deep link)

    fun handleSharedText(text: String) {
        lastInteractionTime = now()
        if (appState == 3) resumeFromInactive()
        val link = SbbShareLink.findIn(text)
        if (link == null) {
            showShareStatus(str(R.string.no_sbb_link))
            return
        }
        val sourceUrl = (link as? SbbShareLink.Short)?.url
        viewModelScope.launch {
            try {
                val route = SbbShareService.shared.resolve(link)
                openSharedRoute(SharedRouteOffer(route, sourceUrl))
            } catch (e: SbbDecodeException) {
                showShareStatus(
                    when (e.reason) {
                        SbbDecodeException.Reason.UNSUPPORTED_VERSION ->
                            str(R.string.sbb_link_unsupported)
                        SbbDecodeException.Reason.NO_RIDE_LEGS ->
                            str(R.string.nothing_to_track)
                        SbbDecodeException.Reason.MALFORMED ->
                            str(R.string.cant_read_link)
                    },
                )
            } catch (e: IOException) {
                showShareStatus(str(R.string.check_connection))
            }
        }
    }

    private suspend fun openSharedRoute(offer: SharedRouteOffer) {
        val existing = pendingRouteStore.current()
        if (existing != null &&
            PendingRouteLogic.fingerprint(existing) != offer.fingerprint()
        ) {
            shareReplaceOffer = offer
            return
        }
        proceedOffer(offer)
    }

    // A board save queues straight away; an SBB share consults the live board.
    private suspend fun proceedOffer(offer: SharedRouteOffer) {
        if (offer.saveOnly) saveOfferAsQueued(offer) else proceedWithSharedRoute(offer)
    }

    fun confirmReplaceSharedRoute() {
        val offer = shareReplaceOffer ?: return
        shareReplaceOffer = null
        viewModelScope.launch { proceedOffer(offer) }
    }

    fun dismissReplaceSharedRoute() {
        shareReplaceOffer = null
    }

    // Save a single board departure as a pending route, so it rides the same
    // distance-aware reminder as an SBB share. Tapping a row tracks now; this
    // explicitly saves for later, which matters most for a far-future departure.
    // Peer of PhoneViewModel.saveDepartureAsPending.
    fun saveDepartureAsPending(departure: Departure) {
        lastInteractionTime = now()
        val station = currentStation
        if (station == null || departure.departureTimestamp == null) {
            showShareStatus(str(R.string.cant_save_departure))
            return
        }
        val offer = SharedRouteOffer(
            route = SharedRoute.forDeparture(station, departure),
            sourceUrl = null,
            saveOnly = true,
        )
        viewModelScope.launch { openSharedRoute(offer) }
    }

    // A live session that keeps running in the background (the foreground-service
    // notification) while the board is shown. Non-null = "Track in the
    // background" is active: the board pins it at the top and tapping it re-opens
    // full tracking. The service's own loop drives the notification meanwhile.
    var backgroundTracked by mutableStateOf<FocusedDeparture?>(null)
        private set
    var backgroundTrackedStation by mutableStateOf<String?>(null)
        private set

    // Tracking-screen "Track in the background": leave the immersive tracking
    // screen for the board but keep the notification tracking. No reminder, no
    // background-location prompt — the foreground service covers it.
    fun trackCurrentInBackground() {
        lastInteractionTime = now()
        val focused = focusedTrain ?: return
        backgroundTracked = focused
        backgroundTrackedStation = currentStation?.name
        // Hand the notification to the service's own loop (the VM is no longer
        // on the tracking screen to push it).
        TrackingSessionBus.appForeground.value = false
        // Exit to the board WITHOUT stopping the service (unlike exitToStationView).
        appState = 0
        focusedTrain = null
        formation = null
        location.setTrackingAccuracy(false)
        consecutiveErrors = 0
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
        returnToNearbyIfLaunched()
    }

    // Board "now tracking" card tapped: re-open the full tracking screen for the
    // session that's been running in the background.
    fun resumeBackgroundTracking() {
        val dep = backgroundTracked ?: return
        backgroundTracked = null
        backgroundTrackedStation = null
        TrackingSessionBus.appForeground.value = true
        beginTracking(dep)
    }

    private fun clearBackgroundTracking() {
        backgroundTracked = null
        backgroundTrackedStation = null
    }

    // Board "now tracking" card stop: end the background session and its
    // notification without re-opening the tracking screen. When a shared route
    // backs the session, X clears the whole journey (route + reminder), matching
    // the old chip's discard — the card is now the single surface for it.
    fun stopBackgroundTracking() {
        clearBackgroundTracking()
        TrackingNotificationService.stop(getApplication())
        viewModelScope.launch {
            if (pendingRouteStore.current() != null) dismissPendingRoute()
        }
    }

    // Start a live background session for a leg the user hasn't opened
    // immersively — a shared route queued far out. The foreground-service
    // notification carries the countdown (paused tier while far: no polling, no
    // GPS), the board shows the now-tracking card, and the pending route +
    // reminder stay as the reboot backstop. No-op if a session already runs.
    private fun enterBackgroundTrack(leg: RouteLeg, station: String?, routeDestination: String?) {
        if (backgroundTracked != null || appState == 2 || !leg.isTrackable) return
        val focused = FocusedDeparture(
            destination = leg.destName,
            departureTimestamp = leg.depTs,
            lineNumber = leg.lineNumber ?: "",
            category = leg.category ?: "",
            trainNumber = leg.trainNumber,
            operatorRef = null,
            delay = 0,
            platform = "",
            platformChanged = false,
            routeDestination = routeDestination,
        )
        backgroundTracked = focused
        backgroundTrackedStation = station
        trackingStartedTs = nowSeconds()
        // Drive the notification from the service's own loop; the VM isn't on the
        // immersive tracking screen.
        TrackingSessionBus.appForeground.value = false
        val snapshot = TrackingSnapshot(
            focused = focused,
            stationId = leg.originId,
            stationName = leg.originName,
            stationLat = leg.originLat,
            stationLon = leg.originLon,
            walkDistMeters = null,
            gpsOk = false,
            startedEpochSeconds = trackingStartedTs,
        )
        TrackingNotificationService.start(getApplication(), snapshot)
        notificationPermissionRequest = true
    }

    // Bypass the nearby flow: show the leg's origin as the sole station and
    // fetch its board; the fetch completion decides track-now vs save-for-later.
    private fun proceedWithSharedRoute(offer: SharedRouteOffer) {
        val index = offer.route.targetRideLegIndex(nowSeconds())
        if (index == null) {
            showShareStatus(str(R.string.trip_underway))
            return
        }
        val leg = offer.route.legs[index]
        val stationId = leg.originId
        if (stationId == null) {
            showShareStatus(str(R.string.cant_read_link))
            return
        }
        pendingShareTrack = offer
        launchStation(stationId, leg.originName, leg.originLat, leg.originLon)
    }

    // Make a specific station the current one without a nearby search: build it,
    // put it in the active mode list, and select it. Peer of Wear's launchStation.
    // Deliberately does NOT touch appState or the departure list, the caller
    // decides whether to show the board (fresh share) or go straight to a
    // countdown (explicit track). lastSearchCoordinate stays at the user's real
    // GPS origin so walk distances and recovery use where they actually are.
    private fun setLaunchedStation(stId: String, name: String?, lat: Double?, lon: Double?) {
        lastInteractionTime = now()
        if (appState == 3) resumeFromInactive()
        val station = Station(
            id = stId,
            name = name ?: str(CoreR.string.station_fallback),
            lat = lat,
            lon = lon,
            mode = currentMode,
        )
        when (currentMode) {
            TransportMode.TRAIN -> trainStations = listOf(station)
            TransportMode.BUS -> busStations = listOf(station)
            TransportMode.TRAM -> tramStations = listOf(station)
            TransportMode.SPECIAL -> specialStations = listOf(station)
        }
        if (currentMode !in availableModes) availableModes = listOf(currentMode)
        stationIndex = 0
        launchedStationActive = true
    }

    // Fresh-share intake: show the origin board and let the fetch decide
    // track-now vs save-for-later. Blanks the list to a spinner while it loads.
    private fun launchStation(stId: String, name: String?, lat: Double? = null, lon: Double? = null) {
        setLaunchedStation(stId, name, lat, lon)
        appState = 0
        departures = emptyList()
        favouriteDepartures = emptyList()
        fetchDepartures(stId)
    }

    // Leave a launched (remote) station and go back to the nearby list at the
    // user's real location. No-op when the current station already came from a
    // nearby search, so the normal tracking-exit path is unchanged.
    private fun returnToNearbyIfLaunched() {
        if (!launchedStationActive) return
        launchedStationActive = false
        trainStations = emptyList()
        busStations = emptyList()
        tramStations = emptyList()
        specialStations = emptyList()
        stationIndex = 0
        departures = emptyList()
        favouriteDepartures = emptyList()
        val coord = location.coordinate.value ?: lastSearchCoordinate
        if (coord != null && SwissBounds.contains(coord.lat, coord.lon)) {
            fetchStations(coord.lat, coord.lon)
        }
        // No coord yet: stations are empty, so onLocationUpdate fetches once GPS arrives.
    }

    // Runs on the departures fetch a shared route triggered: train on the
    // board → track it now, keeping the route stored for leg advancement;
    // not there yet → queue it and say so.
    private suspend fun tryEnterPendingShareTrack() {
        val offer = pendingShareTrack ?: return
        pendingShareTrack = null
        val forced = offer.forceLegIndex
        val index = forced ?: offer.route.targetRideLegIndex(nowSeconds()) ?: return
        val leg = offer.route.legs.getOrNull(index) ?: return
        val pending = pendingFor(offer, index)
        val now = nowSeconds()
        val match = matchDeparture(departures, leg)
        when {
            // On the live board: track it with real delay/platform.
            match != null -> {
                pendingRouteStore.save(pending.copy(status = PendingRoute.STATUS_TRACKING))
                PendingRouteNotifier.schedule(getApplication(), pending, now)
                selectDepartureImpl(match, pending.finalDestination)
            }
            // Not on the board yet, but the user explicitly opened it (forced),
            // or it's close enough to resume: open a local countdown that
            // survives until the train departs. Never wall the user out.
            leg.isTrackable && (forced != null || PendingRouteLogic.isResumable(pending, now)) -> {
                pendingRouteStore.save(pending.copy(status = PendingRoute.STATUS_TRACKING))
                PendingRouteNotifier.schedule(getApplication(), pending, now)
                enterProtectedTrack(leg, pending.finalDestination)
            }
            // Far out or untrackable (e.g. outside Switzerland): queue + remind.
            else -> saveOfferAsQueued(offer)
        }
    }

    // Preserve an existing route's id + muted legs when resuming/tracking it;
    // a fresh share mints a new PendingRoute.
    private fun pendingFor(offer: SharedRouteOffer, index: Int): PendingRoute =
        offer.existing?.copy(cursor = index)
            ?: PendingRoute.from(
                route = offer.route,
                targetLegIndex = index,
                id = UUID.randomUUID().toString(),
                createdTs = nowSeconds(),
                sourceUrl = offer.sourceUrl,
            )

    private suspend fun saveOfferAsQueued(offer: SharedRouteOffer) {
        val index = offer.forceLegIndex ?: offer.route.targetRideLegIndex(nowSeconds()) ?: return
        val pending = pendingFor(offer, index).copy(status = PendingRoute.STATUS_SAVED)
        pendingRouteStore.save(pending)
        // Pin the reminder's walk time to where the user actually is now, not the
        // last nearby-search coordinate (only refreshed on a ~500 m move), so the
        // distance-aware lead matches the live walk shown on the board.
        location.saveLastKnownCoordinate()
        PendingRouteNotifier.schedule(getApplication(), pending, nowSeconds())
        notificationPermissionRequest = true
        syncReminderTracking()
        showShareStatus(str(R.string.saved_will_remind))
        // Don't strand the user on the remote origin board. Return to their real
        // location, then start a live background session for the queued leg so the
        // countdown card + notification appear (paused while far, ramping near
        // departure). The reminder above stays as the reboot backstop.
        returnToNearbyIfLaunched()
        if (pending.legs.isNotEmpty()) {
            val leg = pending.legs[index.coerceIn(0, pending.legs.size - 1)]
            enterBackgroundTrack(leg, leg.originName, pending.finalDestination)
        }
    }

    // Pending-route lifecycle: normalize against the clock, expire, prompt.
    // Safe to call from anywhere. Advancement is time-derived and idempotent.

    // Normalise the stored route (advance past departed legs, reschedule the
    // reminder) on app open. The saved-route chip shows the current leg; the user
    // resumes from there, so there's no separate prompt.
    private suspend fun refreshPendingRoute() {
        val current = pendingRouteStore.current() ?: return
        val normalized = PendingRouteLogic.normalize(current, nowSeconds())
        if (normalized == null) {
            pendingRouteStore.clear()
            PendingRouteNotifier.cancel(getApplication())
            showShareStatus(str(R.string.route_passed_fmt, current.finalDestination))
            return
        }
        if (normalized != current) {
            pendingRouteStore.save(normalized)
            PendingRouteNotifier.schedule(getApplication(), normalized, nowSeconds())
        }
        // A process kill (OnePlus reaps background apps aggressively) drops the
        // in-memory session while the route persists, so on reopen the board
        // would fall back to the old chip. Re-establish the live session here so
        // the green now-tracking card is the single top surface; the tiered
        // engine keeps a far session paused and free. No-op if a session already
        // runs, we're mid immersive-tracking, or the current leg isn't trackable.
        normalized.legs.getOrNull(normalized.cursor)?.let { leg ->
            enterBackgroundTrack(leg, leg.originName, normalized.finalDestination)
        }
    }

    // Notification tap / route-view "Track now" on the current leg. An explicit
    // resume always opens the countdown, even hours out, a live board match gives
    // real delay/platform, otherwise a local countdown. Never re-queues.
    fun resumePendingRoute() {
        val route = pendingRoute ?: return
        viewModelScope.launch {
            val normalized = PendingRouteLogic.normalize(route, nowSeconds()) ?: run {
                refreshPendingRoute()
                return@launch
            }
            trackLegImpl(normalized, normalized.cursor)
        }
    }

    // Route-view "Track now" on any trackable leg (may jump ahead to a later
    // connection). Untrackable legs (walk / outside Switzerland) are ignored.
    fun trackLeg(index: Int) {
        val route = pendingRoute ?: return
        viewModelScope.launch {
            val normalized = PendingRouteLogic.normalize(route, nowSeconds()) ?: run {
                refreshPendingRoute()
                return@launch
            }
            trackLegImpl(normalized, index)
        }
    }

    // The countdown is fully local (derived from the leg's departure time), so
    // an explicit tap enters it immediately: no board fetch gates it, the screen
    // never blanks, and a slow or failed network can't bounce the user back to
    // their location. The origin becomes the current station so walk distance,
    // formation and live enrichment target it; beginTracking's timer then fetches
    // that board in the background to upgrade platform/delay when it appears.
    private fun trackLegImpl(route: PendingRoute, index: Int) {
        val leg = route.legs.getOrNull(index)?.takeIf { it.isTrackable } ?: return
        val stationId = leg.originId ?: return
        val pending = route.copy(cursor = index, status = PendingRoute.STATUS_TRACKING)
        viewModelScope.launch {
            pendingRouteStore.save(pending)
            PendingRouteNotifier.schedule(getApplication(), pending, nowSeconds())
        }
        setLaunchedStation(stationId, leg.originName, leg.originLat, leg.originLon)
        enterProtectedTrack(leg, route.finalDestination)
    }

    // Route-view per-leg track/notify toggle. Reschedules the reminder so a
    // muted current leg drops its notification, an un-muted one restores it.
    fun setLegMuted(index: Int, muted: Boolean) {
        viewModelScope.launch {
            pendingRouteStore.setLegMuted(index, muted)
            pendingRouteStore.current()?.let {
                PendingRouteNotifier.schedule(getApplication(), it, nowSeconds())
            }
        }
    }

    // Platform per ride leg for the route view, keyed by leg index. Platforms
    // aren't in the shared link, they come from the live board and only exist
    // close to departure, so this fetches each near-term leg's origin board
    // once and matches it. Legs hours out simply have no platform yet.
    var routeLegPlatforms by mutableStateOf<Map<Int, String>>(emptyMap())
        private set

    fun loadRoutePlatforms(route: PendingRoute) {
        routeLegPlatforms = emptyMap()
        viewModelScope.launch {
            val now = nowSeconds()
            val result = mutableMapOf<Int, String>()
            route.legs.forEachIndexed { i, leg ->
                if (leg.type != LegType.RIDE || !leg.isTrackable) return@forEachIndexed
                if (leg.depTs - now > 60 * 60) return@forEachIndexed // not on the board yet
                val stationId = leg.originId ?: return@forEachIndexed
                val board = runCatching { api.fetchDepartures(stationId) }.getOrNull() ?: return@forEachIndexed
                matchDeparture(board.departures, leg)?.platform?.takeIf { it.isNotEmpty() }?.let { result[i] = it }
            }
            routeLegPlatforms = result
        }
    }

    fun dismissPendingRoute() {
        viewModelScope.launch {
            pendingRouteStore.clear()
            PendingRouteNotifier.cancel(getApplication())
            reminderNotifyTs = null
            RouteDistanceTracker.stop(getApplication())
        }
    }

    fun clearNotificationPermissionRequest() {
        notificationPermissionRequest = false
    }

    // A tracking session ended (departed or user-exited). The route only
    // reacts when it was tracking that exact departure: post-departure it
    // advances to the next leg, an early exit reverts to saved.
    private fun onTrackingEnded(endedDepTs: Long?) {
        if (endedDepTs == null) return
        viewModelScope.launch {
            val current = pendingRouteStore.current() ?: return@launch
            val next = PendingRouteLogic.advancedAfterTracking(current, endedDepTs, nowSeconds())
            if (next == null) {
                pendingRouteStore.clear()
                PendingRouteNotifier.cancel(getApplication())
            } else if (next != current) {
                pendingRouteStore.save(next)
                PendingRouteNotifier.schedule(getApplication(), next, nowSeconds())
            }
        }
    }

    private fun showShareStatus(status: String) {
        shareStatus = status
    }

    fun clearShareStatus() {
        shareStatus = null
    }
}

// A decoded shared route awaiting a decision (auto-track, queue, or the
// user's replace confirmation). forceLegIndex + existing are set when resuming
// or tracking a leg the user already saved: force enters tracking regardless of
// the resume window, and existing preserves the stored id + muted legs.
data class SharedRouteOffer(
    val route: SharedRoute,
    val sourceUrl: String?,
    val forceLegIndex: Int? = null,
    val existing: PendingRoute? = null,
    // A board "Remind me" save always queues for a reminder, never tracks now
    // (tapping the row already tracks). SBB shares leave this false and decide
    // track-vs-queue from the live board.
    val saveOnly: Boolean = false,
) {
    fun fingerprint(): String = PendingRouteLogic.fingerprint(route.legs)
}

// The next ride leg while tracking a shared route: where the user changes, the
// onward train, and the connection buffer in minutes.
data class OnwardConnection(
    val changeStation: String,
    val leg: RouteLeg,
    val legIndex: Int,
    val changeMinutes: Long,
)
