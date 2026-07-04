package com.evanjt.traintime.ui

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.glance.appwidget.updateAll
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
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
import com.evanjt.traintime.data.model.PinnedStation
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.core.sync.TrackCommand
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.core.sync.WearStateSync
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.data.prefs.MyStationsStore
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.HapticService
import com.evanjt.traintime.domain.LocationService
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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

    // Pinned "My stations" — bubble to the front of the nearby list.
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

    // Garmin mirroring (optional overlay; off → the watch runs entirely on its own).
    // Cached eligible Garmin device IDs so mirror pushes skip a per-change BLE
    // app-installed sweep; refreshed whenever watch links are.
    private var garminTargetIds: List<String> = emptyList()
    private var mirrorToWatch = true
    private var mirrorJob: Job? = null
    private var lastPushedLoc: LatLon? = null
    private var lastLocPushTime = 0L

    // Watch-app liveness. The watch announces itself (hello/alive/bye); the phone never
    // pings (a phone message can wake a closed watch-app). A fresh alive → green, a stale
    // one or a bye → amber, and a press shows the spinner until the watch says hello.
    private var heartbeatJob: Job? = null
    private var lastAliveTime = 0L
    var watchChecking by mutableStateOf(false)
        private set
    var watchAlive by mutableStateOf(false)
        private set
    // A Garmin watch is paired but not currently connected (off / out of range) → grey.
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

        viewModelScope.launch {
            defaultMode = prefs.defaultModeNow()
            currentMode = defaultMode
        }
        viewModelScope.launch {
            // Keep the default mode live and synced — a watch-originated change
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
    }

    // On foreground: find eligible watches (connected + TrainTime installed) for the header
    // indicator and settings list, then feed the current location to any already-open watch.
    // The BLE sweep finishes after the first location emits, so without this push a watch
    // sitting on "Not in Switzerland" would never pick up the phone's position until it moved.
    private fun refreshWatchLinksOnAppear() {
        viewModelScope.launch {
            val wear = wearSync.connectedWatchNames().map { WatchLink(it, PhoneWatchType.WEAR, true) }
            val garmin = garminService.eligibleDevices()
            garminTargetIds = garmin.map { it.id }
            watchLinks = wear + buildGarminLinks(garmin)
            updateGarminGrey(garmin)
            pushLocationNow()
            startHeartbeat()
        }
    }

    // Launch TrainTime on the connected Garmin watch(es) — the one place we legitimately
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
            // Already open — just push the current view to it, no relaunch needed.
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
                watchAlive = isAliveFresh()
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
                    watchAlive = garminTargetIds.isNotEmpty() && isAliveFresh()
                    // Grey when a watch is paired but not reachable. knownDevices is a local
                    // SDK lookup (no BLE), so it's cheap to re-evaluate each tick.
                    watchKnownButDisconnected =
                        garminTargetIds.isEmpty() && !watchAlive && garminService.hasKnownDevices()
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

    private fun updateGarminGrey(connected: List<GarminConnectIQService.GarminDevice>) {
        watchKnownButDisconnected =
            connected.isEmpty() && !watchAlive && garminService.hasKnownDevices()
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    // An alive/hello within the last few heartbeat intervals counts as alive (the watch
    // beats every ~7s, so tolerate a couple of drops).
    private fun isAliveFresh(): Boolean = now() - lastAliveTime <= 20_000

    fun onDisappear() {
        // The widget is only visible once we background; seed its cache with what
        // was on screen so it shows live data without its own refresh tap.
        seedWidgetCache()
        location.stop()
        stopTimer()
        stopHeartbeat()
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

        // Movement detection (station view only) — refresh in place
        val lastSearch = lastSearchCoordinate
        if (appState <= 1 && lastSearch != null && location.hasMovedSignificantly(lastSearch)) {
            fetchStations(coord.lat, coord.lon)
            return
        }

        // Update walk distance to current station. lat/lon are nullable :core
        // properties, so capture locals — cross-module props don't smart-cast.
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

        val focused = FocusedDeparture(
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
        focusedTrain = focused
        appState = 2
        location.setTrackingAccuracy(true)
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = 0
        formation = null

        // Fetch formation for rail departures
        val trainNumber = dep.trainNumber
        val stationId = currentStation?.id
        if (trainNumber != null && Formation.isRailCategory(dep.category) && stationId != null) {
            val date = formationDateString()
            viewModelScope.launch {
                formation = runCatching {
                    api.fetchFormation(trainNumber, date, stationId, dep.operatorRef)
                }.getOrNull()
            }
        }

        startTimer(Timing.TRACKING_REFRESH_INTERVAL)
        haptics.shortPulse()

        // Mirror the same focused train onto the watch (immediate — a tap is a
        // strong, deliberate action). Keeps the manual "Send to Watch" too.
        mirrorToGarmin(TrackCommand.from(focused, stationId).toGarminMap())
    }

    fun enterInactiveState() {
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

    fun updateDefaultMode(mode: TransportMode) {
        defaultMode = mode
        viewModelScope.launch { prefs.setDefaultMode(mode) }
    }

    fun updateAppearanceMode(mode: String) {
        viewModelScope.launch { prefs.setAppearanceMode(mode) }
    }

    fun markOnboardingSeen() {
        viewModelScope.launch { prefs.markOnboardingSeen() }
    }

    fun replayOnboarding() {
        viewModelScope.launch { prefs.markOnboardingUnseen() }
    }

    fun incrementReviewTrackCount() {
        viewModelScope.launch { prefs.incrementReviewTrackCount() }
    }

    fun markReviewPrompted(version: String) {
        viewModelScope.launch { prefs.setReviewPromptedVersion(version) }
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
            val wear = wearSync.connectedWatchNames().map { WatchLink(it, PhoneWatchType.WEAR, true) }
            // eligibleDevices are connected + have TrainTime installed, so all are reachable.
            val garmin = garminService.eligibleDevices()
            garminTargetIds = garmin.map { it.id }
            watchLinks = wear + buildGarminLinks(garmin)
            updateGarminGrey(garmin)
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
    // closed watch-app.
    private fun canMessageWatch(): Boolean = mirrorToWatch && garminTargetIds.isNotEmpty() && watchAlive

    // Debounced variant for rapid changes (mode cycling, station scrolling) — the
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
        if (!canMessageWatch()) return
        val last = lastPushedLoc
        val movedEnough = last == null ||
            GeoUtils.haversineDistance(last.lat, last.lon, coord.lat, coord.lon) >= 100.0
        if (!movedEnough && now() - lastLocPushTime < 10_000) return
        lastPushedLoc = coord
        lastLocPushTime = now()
        val payload = WearSync.garminLocationPayload(coord.lat, coord.lon)
        viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
    }

    // Force-push the current location to all eligible watches, bypassing the
    // movement/time debounce. Used on app open and when opening the watch app.
    private fun pushLocationNow() {
        if (!canMessageWatch()) return
        val coord = location.coordinate.value ?: return
        lastPushedLoc = coord
        lastLocPushTime = now()
        val payload = WearSync.garminLocationPayload(coord.lat, coord.lon)
        viewModelScope.launch { garminTargetIds.forEach { garminService.send(it, payload) } }
    }

    // Bring a freshly-opened watch in line with the phone: the tracked train if we're
    // tracking, otherwise the current station, plus the current location. This is what
    // makes the watch button (header or tracking screen) open the watch onto the same view.
    private fun syncCurrentStateToWatch() {
        if (!canMessageWatch()) return
        pushLocationNow()
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
        val wear = wearSync.connectedWatchNames().mapIndexed { i, name ->
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

    // Applies a state sync pushed from a watch (defaultMode). Garmin sends this via the
    // Connect IQ message channel; Wear arrives through the listener service / DataClient.
    private fun applyReceivedWatchContext(ctx: Map<String, Any?>) {
        // Liveness announcement — the watch app is open and reachable (hello on launch,
        // alive as its periodic heartbeat).
        if (ctx["kind"] == "hello" || ctx["kind"] == "alive") {
            val wasAlive = watchAlive
            lastAliveTime = now()
            watchAlive = true
            watchChecking = false
            // A freshly-online watch jumps to whatever the phone is showing (tracking
            // train, or current station) and gets seeded with the phone's location.
            if (!wasAlive) syncCurrentStateToWatch()
            return
        }
        // The watch app is closing — flip the indicator straight away.
        if (ctx["kind"] == "bye") {
            lastAliveTime = 0L
            watchAlive = false
            watchChecking = false
            return
        }
        // The watch is asking for the phone's location (its own GPS is weak).
        if (ctx["kind"] == "reqLoc") {
            replyWithLocation()
            return
        }
        val modeRaw = (ctx["defaultMode"] as? Number)?.toInt() ?: return
        viewModelScope.launch { prefs.setDefaultMode(TransportMode.fromRaw(modeRaw)) }
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
        lastInteractionTime = now()
        appState = 0
        location.setTrackingAccuracy(false)
        focusedTrain = null
        formation = null
        consecutiveErrors = 0
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
        // Mirror the exit so the watch leaves tracking and returns to its station view.
        if (wasTracking) mirrorToGarmin(mapOf("action" to "back"))
    }

    // Mode navigation

    fun selectMode(mode: TransportMode) {
        lastInteractionTime = now()
        if (mode == currentMode) return
        currentMode = mode
        stationIndex = 0
        adoptEmbeddedOrFetch()
        mirrorToGarminDebounced { WearSync.garminModePayload(mode.raw) }
    }

    fun selectStation(index: Int) {
        lastInteractionTime = now()
        if (index < 0 || index >= stations.size) return
        stationIndex = index
        showStationPicker = false
        adoptEmbeddedOrFetch()
        currentStation?.let { st ->
            mirrorToGarminDebounced { WearSync.garminStationPayload(st.id, st.name ?: "Station", st.lat, st.lon) }
        }
    }

    private fun adoptEmbeddedOrFetch() {
        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            viewModelScope.launch { favouriteDepartures = extractFavouritesFromCurrent(deps) }
            lastFetchTime = now()
        } else {
            departures = emptyList()
            favouriteDepartures = emptyList()
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

        val matches = departures.filter {
            it.destination == focused.destination && it.minutesUntil >= -1
        }
        val best = matches.minByOrNull {
            kotlin.math.abs(it.minutesUntil.toDouble() - focused.minutesUntil(nowS))
        }
        if (best == null) {
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

    // API calls

    private fun fetchStations(lat: Double, lon: Double) {
        if (requestInFlight) return
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

    fun fetchDepartures(stationId: String) {
        viewModelScope.launch { fetchDeparturesAsync(stationId) }
    }

    private suspend fun fetchDeparturesAsync(stationId: String) {
        if (requestInFlight) return
        requestInFlight = true
        requestStartTime = now()

        try {
            val favParam = favouritesStore.favouritesParam(stationId)
            val result = api.fetchDepartures(stationId, favParam)
            requestInFlight = false
            requestStartTime = null
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
        } catch (e: Exception) {
            requestInFlight = false
            requestStartTime = null
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

        // traintime://sbbshare — just open the app (SBB share trigger)
        if (uri.host == "sbbshare") {
            if (appState == 3) resumeFromInactive()
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
}
