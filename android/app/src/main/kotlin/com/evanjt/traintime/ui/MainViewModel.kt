package com.evanjt.traintime.ui

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.glance.appwidget.updateAll
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.evanjt.traintime.BuildConfig
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
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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

class MainViewModel(application: Application) : AndroidViewModel(application) {
    companion object {
        // Shown (and the gate for the faint Swiss-outline backdrop) when located outside
        // Switzerland with no stations to show.
        const val OUT_OF_BOUNDS_STATUS = "Not in Switzerland"
    }

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
    var status by mutableStateOf("GPS: Searching...")
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
    // event: the first saved route asks contextually (API 33+).
    var pendingRoute by mutableStateOf<PendingRoute?>(null)
        private set
    var resumeOffer by mutableStateOf<Departure?>(null)
        private set
    var notificationPermissionRequest by mutableStateOf(false)
        private set
    private var resumeCheckInFlight = false

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
        get() = currentStation?.walkInfo(stationIndex, stations.size) ?: ""

    val stationName: String
        get() = currentStation?.name ?: "Station"

    init {
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
                // Mirror to the watch chip; the echo guard absorbs no-ops.
                runCatching { wearSync.pushState() }
            }
        }

        // Wear liveness (hello/alive/bye/reqLoc) relayed by PhoneWearListenerService,
        // the Data Layer peer of the Garmin path through applyReceivedWatchContext.
        viewModelScope.launch { WearLivenessBus.events.collect { handleWearLiveness(it) } }

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
                if (denied && stations.isEmpty()) status = "Location permission required"
            }
        }
    }

    // Lifecycle

    fun onAppear() {
        lastInteractionTime = now()
        viewModelScope.launch {
            location.start()
            if (location.loadedFromCache) loadedFromCache = true
        }
        startTimer(if (appState == 2) Timing.TRACKING_REFRESH_INTERVAL else Timing.NORMAL_REFRESH_INTERVAL)
        refreshWatchLinksOnAppear()
        viewModelScope.launch { refreshPendingRoute() }
        syncReminderTracking()
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
                showWatchStatus("No watch connected")
                return@launch
            }
            // Already open, just push the current view to it, no relaunch needed.
            if (watchAlive) {
                syncCurrentStateToWatch()
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
                val wasAlive = wearAliveFresh()
                wearLastAlive = now()
                wearNodesPresent = true
                recomputeWatchAlive()
                // A freshly-online watch jumps to whatever the phone is showing.
                if (!wasAlive) syncCurrentStateToWear()
            }
            WearSync.KIND_BYE -> {
                wearLastAlive = 0L
                recomputeWatchAlive()
            }
            WearSync.KIND_REQ_LOC -> replyWithLocationToWear()
        }
    }

    fun onDisappear() {
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
            if (stations.isEmpty()) status = "GPS: Searching..."
            return
        }

        // Keep a connected watch fed with the phone's location as a GPS fallback.
        maybePushLocationToWatch(coord)

        if (!SwissBounds.contains(coord.lat, coord.lon) && stations.isEmpty()) {
            status = OUT_OF_BOUNDS_STATUS
            return
        }

        // Skip station search in tracking/inactive (still update GPS above)
        if (appState >= 2) return

        if (loadedFromCache && (location.gpsQuality == GpsQuality.GOOD || location.gpsQuality == GpsQuality.POOR)) {
            loadedFromCache = false
            if (!requestInFlight) {
                if (stations.isEmpty()) status = "Updating stations..."
                fetchStations(coord.lat, coord.lon)
            }
            return
        }

        if (stations.isEmpty() && !requestInFlight) {
            status = "Finding stations..."
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

    private fun selectDepartureImpl(dep: Departure) {
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
            )
        )
        maybeRequestReview()
    }

    // Track a shared-route leg whose train isn't on the live board yet. The
    // countdown is fully local (derived from depTs), so it runs without a board
    // match; updateFocusedTrain keeps it until the train actually departs, then
    // a live board match upgrades it with delay/platform.
    private fun enterProtectedTrack(leg: RouteLeg) {
        beginTracking(
            FocusedDeparture(
                destination = leg.destName,
                departureTimestamp = leg.depTs,
                lineNumber = leg.lineNumber ?: "",
                category = leg.category ?: "",
                trainNumber = leg.trainNumber,
                operatorRef = null,
                delay = 0,
                platform = "",
                platformChanged = false,
            )
        )
    }

    // Shared tracking entry: from a real board tap or a synthesised shared-route
    // leg. Everything downstream (timer cadence, watch/Garmin mirror, formation)
    // is identical once we have a FocusedDeparture.
    private fun beginTracking(focused: FocusedDeparture) {
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

        // Mirror the same focused train onto the watch (immediate, a tap is a
        // strong, deliberate action). Keeps the manual "Send to Watch" too.
        val trackCmd = TrackCommand.from(focused, stationId)
        mirrorToGarmin(trackCmd.toGarminMap())
        if (canMessageWear()) viewModelScope.launch { wearSync.sendTrack(trackCmd) }
    }

    fun enterInactiveState() {
        onTrackingEnded(if (appState == 2) focusedTrain?.departureTimestamp else null)
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

    fun setDistanceAwareReminder(value: Boolean) {
        viewModelScope.launch {
            prefs.setDistanceAwareReminder(value)
            if (value && prefs.backgroundReminderTracking.first()) maybeRequestBackgroundLocation()
            syncReminderTracking()
        }
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
                    "Distance test",
                    "Turn on location and open the app near a station first.",
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
                "Distance test: $originName",
                "${dist.toInt()} m away (~$walkMin min walk). Reminder would fire $leadMin min before departure.",
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
                stationName = station.name ?: "Station",
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
        }
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
                mirrorToWear(WearCommand("station", stId = st.id, name = st.name ?: "Station", lat = st.lat, lon = st.lon))
            }
        }
    }

    // Reply to a Wear watch's explicit reqLoc with the phone's current coordinate.
    private fun replyWithLocationToWear() {
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
        pushLocationNow()
        // Re-seed favourites so a freshly-opened watch unions in anything it lacks.
        pushFavouritesToGarmin(favouritesList)
        val focused = focusedTrain
        val payload = if (appState == 2 && focused != null) {
            TrackCommand.from(focused, currentStation?.id).toGarminMap()
        } else {
            currentStation?.let { st ->
                WearSync.garminStationPayload(st.id, st.name ?: "Station", st.lat, st.lon)
            }
        } ?: return
        viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
    }

    // Reply to a watch's explicit reqLoc with the phone's current coordinate.
    private fun replyWithLocation() {
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
                showWatchStatus("No watch connected")
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
                showWatchStatus("Update TrainTime on your watch (${version ?: WearSync.LEGACY_VERSION_NAME})")
                return@launch
            }
            val cmd = TrackCommand.from(focused, stationId)
            val ok = when (watch.type) {
                PhoneWatchType.WEAR -> wearSync.sendTrack(cmd) > 0
                PhoneWatchType.GARMIN -> {
                    val deviceId = watch.id.removePrefix("garmin_")
                    garminService.sendTrack(deviceId, cmd.toGarminMap())
                }
            }
            showWatchStatus(if (ok) "Sent to ${watch.name}" else "Failed to send")
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
            if (!watchAlive && hasGarminLink) openWatchApp() else sendToWatch()
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
            // A freshly-online watch jumps to whatever the phone is showing (tracking
            // train, or current station) and gets seeded with the phone's location.
            if (!wasAlive) syncCurrentStateToWatch()
            return
        }
        // The watch app is closing, flip the indicator straight away. The high
        // water mark stays: bye after alive is exactly what the ping gate reads.
        if (ctx["kind"] == "bye") {
            garminLastAlive = 0L
            garminLastBye = now()
            recomputeWatchAlive()
            watchChecking = false
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
            originName = ctx["stName"] as? String ?: "Station",
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
            mirrorToGarminDebounced { WearSync.garminStationPayload(st.id, st.name ?: "Station", st.lat, st.lon) }
            mirrorToWearDebounced { WearCommand("station", stId = st.id, name = st.name ?: "Station", lat = st.lat, lon = st.lon) }
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

        // Match by train number when we have one (a protected shared-route leg
        // carries it), so live platform/delay are adopted even though the leg's
        // destName is the alight stop, not the board's terminus. Fall back to
        // destination for board taps that lack a train number (buses/trams).
        val matches = departures.filter {
            (it.destination == focused.destination ||
                (focused.trainNumber != null && it.trainNumber == focused.trainNumber)) &&
                it.minutesUntil >= -1
        }
        val best = matches.minByOrNull {
            kotlin.math.abs(it.minutesUntil.toDouble() - focused.minutesUntil(nowS))
        }
        if (best == null) {
            // A still-future train just isn't on the board yet (a shared route
            // opened early, before it reaches the 20-row horizon). Keep the
            // local countdown; only give up once it has actually departed.
            if (nowS < focused.departureTimestamp + PendingRouteLogic.GRACE_SEC) return
            haptics.shortPulse()
            exitToStationView()
            return
        }

        var updated = focused
        if (best.platform != focused.platform && best.platform.isNotEmpty()) {
            if (best.platformChanged) haptics.doublePulse()
            updated = updated.copy(platform = best.platform, platformChanged = best.platformChanged)
        }
        focusedTrain = updated.copy(delay = best.delay)
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
            if (gpsQuality == GpsQuality.UNAVAILABLE) return "No GPS"
            val absBuf = kotlin.math.abs(buf)
            if (absBuf < 0.5) return "On time"
            val unit = if (absBuf < 1.5) "${(absBuf * 60).toInt()}s" else "${absBuf.toInt()} min"
            return if (buf > 0) "$unit ahead" else "$unit behind"
        }

    // Resolved to a palette colour in the composable so it follows light/dark.
    val trackingStatus: TrackingStatus
        get() {
            if (gpsQuality == GpsQuality.UNAVAILABLE) return TrackingStatus.NO_GPS
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

    // While tracking a shared-route leg, the next ride leg of the same route is
    // the onward connection: shown under the countdown, tappable to jump onto
    // it early. Matched by departure time so an unrelated track shows nothing.
    val onwardConnection: OnwardConnection?
        get() {
            val focused = focusedTrain ?: return null
            val route = pendingRoute ?: return null
            val curIdx = route.legs.indexOfFirst {
                it.type == LegType.RIDE && it.depTs == focused.departureTimestamp
            }
            if (curIdx < 0) return null
            val curLeg = route.legs[curIdx]
            val nextIdx = (curIdx + 1 until route.legs.size)
                .firstOrNull { route.legs[it].type == LegType.RIDE } ?: return null
            val next = route.legs[nextIdx]
            val changeMinutes = ((next.depTs - curLeg.arrTs) / 60).coerceAtLeast(0)
            return OnwardConnection(curLeg.destName, next, nextIdx, changeMinutes)
        }

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

                if (stations.isEmpty()) status = "No stations nearby"
            } catch (e: Exception) {
                requestInFlight = false
                requestStartTime = null
                handleError(e, "Stations")
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
            handleError(e, "Departures")
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
            is TrainApiException.RateLimited -> "Rate limited"
            is TrainApiException.Http -> "$context: ${error.code}"
            is TrainApiException.NoData -> "$context error"
            is TrainApiException.Network -> "No connection"
            else -> "$context error"
        }
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

        // traintime://resumeroute: reminder notification tap.
        if (uri.host == "resumeroute") {
            if (appState == 3) resumeFromInactive()
            viewModelScope.launch { refreshPendingRoute() }
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
            showShareStatus("No SBB trip link found")
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
                            "This SBB link format isn't supported yet"
                        SbbDecodeException.Reason.NO_RIDE_LEGS ->
                            "Nothing to track in this trip"
                        SbbDecodeException.Reason.MALFORMED ->
                            "Couldn't read this trip link"
                    },
                )
            } catch (e: IOException) {
                showShareStatus("Couldn't open the link. Check your connection")
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
            showShareStatus("Couldn't save this departure")
            return
        }
        val offer = SharedRouteOffer(
            route = SharedRoute.forDeparture(station, departure),
            sourceUrl = null,
            saveOnly = true,
        )
        viewModelScope.launch { openSharedRoute(offer) }
    }

    // Bypass the nearby flow: show the leg's origin as the sole station and
    // fetch its board; the fetch completion decides track-now vs save-for-later.
    private fun proceedWithSharedRoute(offer: SharedRouteOffer) {
        val index = offer.route.targetRideLegIndex(nowSeconds())
        if (index == null) {
            showShareStatus("This trip is already underway or finished")
            return
        }
        val leg = offer.route.legs[index]
        val stationId = leg.originId
        if (stationId == null) {
            showShareStatus("Couldn't read this trip link")
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
            name = name ?: "Station",
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
                selectDepartureImpl(match)
            }
            // Not on the board yet, but the user explicitly opened it (forced),
            // or it's close enough to resume: open a local countdown that
            // survives until the train departs. Never wall the user out.
            leg.isTrackable && (forced != null || PendingRouteLogic.isResumable(pending, now)) -> {
                pendingRouteStore.save(pending.copy(status = PendingRoute.STATUS_TRACKING))
                PendingRouteNotifier.schedule(getApplication(), pending, now)
                enterProtectedTrack(leg)
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
        showShareStatus("Saved. We'll remind you before departure")
        // Don't strand the user on the remote origin board, the queued route
        // lives in the chip now. Return to their real location.
        returnToNearbyIfLaunched()
    }

    // Pending-route lifecycle: normalize against the clock, expire, prompt.
    // Safe to call from anywhere. Advancement is time-derived and idempotent.

    private suspend fun refreshPendingRoute(prompt: Boolean = true) {
        val current = pendingRouteStore.current() ?: return
        val normalized = PendingRouteLogic.normalize(current, nowSeconds())
        if (normalized == null) {
            pendingRouteStore.clear()
            PendingRouteNotifier.cancel(getApplication())
            showShareStatus("Saved route to ${current.finalDestination} has passed")
            return
        }
        if (normalized != current) {
            pendingRouteStore.save(normalized)
            PendingRouteNotifier.schedule(getApplication(), normalized, nowSeconds())
        }
        if (prompt && appState != 2 &&
            normalized.status != PendingRoute.STATUS_TRACKING &&
            PendingRouteLogic.isResumable(normalized, nowSeconds())
        ) {
            offerResume(normalized)
        }
    }

    // One-shot board check for the resume prompt, outside the normal fetch
    // machinery so it can't disturb the visible station.
    private suspend fun offerResume(route: PendingRoute) {
        if (resumeCheckInFlight || resumeOffer != null) return
        val leg = route.currentLeg ?: return
        val stationId = leg.originId ?: return
        resumeCheckInFlight = true
        try {
            val board = runCatching { api.fetchDepartures(stationId) }.getOrNull() ?: return
            resumeOffer = matchDeparture(board.departures, leg)
        } finally {
            resumeCheckInFlight = false
        }
    }

    // Notification tap / resume dialog Track / route-view "Track now" on the
    // current leg. An explicit resume always opens the countdown, even hours
    // out, a live board match gives real delay/platform, otherwise a local
    // countdown. Never re-queues.
    fun resumePendingRoute() {
        val route = pendingRoute ?: return
        resumeOffer = null
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
        resumeOffer = null
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
        enterProtectedTrack(leg)
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

    fun deferResume() {
        resumeOffer = null
    }

    fun dismissPendingRoute() {
        resumeOffer = null
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
