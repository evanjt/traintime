package com.evanjt.traintime.wear

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.evanjt.traintime.SwissBounds
import com.evanjt.traintime.Timing
import com.evanjt.traintime.core.sync.ReminderCommand
import com.evanjt.traintime.core.sync.TrackCommand
import com.evanjt.traintime.core.sync.WearCommand
import com.evanjt.traintime.core.sync.WearCommandBus
import com.evanjt.traintime.core.sync.WearStateSync
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.core.sync.WearSyncPort
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
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.data.prefs.MyStationsStore
import com.evanjt.traintime.data.prefs.PendingRouteStore
import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import com.evanjt.traintime.data.sbb.matchDeparture
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.HapticService
import com.evanjt.traintime.domain.LocationService
import com.evanjt.traintime.domain.PendingRouteLogic
import com.evanjt.traintime.review.ReviewGate
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class TrackingStatus { NO_GPS, AHEAD, ON_TIME, BEHIND }

// Wear port of PhoneViewModel.swift / MainViewModel, the watch fetches
// independently (not a thin client) and keeps the same orchestration. Drops the
// phone-only widget seeding, deep links and Glance. appState: 0 = station view,
// 2 = focused tracking, 3 = inactive.
class WearViewModel(
    application: Application,
    private val wearSync: WearSyncPort,
) : AndroidViewModel(application) {
    // The default ViewModel factory finds this one; tests inject a fake port.
    constructor(application: Application) : this(application, WearStateSync.get(application))

    val prefs = AppPrefs(application)
    val favouritesStore = FavouritesStore(application)
    val myStationsStore = MyStationsStore(application)
    val location = LocationService(application, prefs)
    val haptics = HapticService(application)
    private val api = TrainApi.shared
    private val pendingRouteStore = PendingRouteStore(application)

    var appState by mutableStateOf(0)
        private set

    // Phone-owned queued route, mirrored read-only over the Data Layer. The
    // watch can start tracking it once its leg is close, never dismiss it.
    var pendingRoute by mutableStateOf<PendingRoute?>(null)
        private set
    private var pendingResumeInFlight = false
    var status by mutableStateOf("GPS: Searching...")
        private set
    var showReviewPrompt by mutableStateOf(false)
        private set
    // Settings "Phone" row, the peer of Garmin's phoneConnected line. Null until queried.
    var phoneConnected by mutableStateOf<Boolean?>(null)
        private set
    // True while a sub-screen (settings / picker) is up: reading it must not
    // trip the station-view inactivity timeout underneath.
    var subScreenOpen = false

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

    var currentMode by mutableStateOf(TransportMode.TRAIN)
        private set
    var availableModes by mutableStateOf(listOf<TransportMode>())
        private set
    var defaultMode by mutableStateOf(TransportMode.TRAIN)
        private set

    var departures by mutableStateOf(listOf<Departure>())
        private set
    var favouriteDepartures by mutableStateOf(listOf<Departure>())
        private set
    var favouritesList by mutableStateOf(listOf<Favourite>())
        private set

    var pinnedStations by mutableStateOf(listOf<PinnedStation>())
        private set
    var pinnedStationIds by mutableStateOf(setOf<String>())
        private set

    var focusedTrain by mutableStateOf<FocusedDeparture?>(null)
        private set
    var formation by mutableStateOf<Formation?>(null)
        private set

    // Transient feedback for the "remind on phone" button; auto-clears.
    var reminderStatus by mutableStateOf<String?>(null)
        private set

    var gpsQuality by mutableStateOf(GpsQuality.UNAVAILABLE)
        private set
    var lastWalkDist by mutableStateOf(0.0)
        private set

    private var requestInFlight = false
    private var requestStartTime: Long? = null
    private var lastFetchTime = 0L
    private var lastSearchCoordinate: LatLon? = null

    // The visible station was launched directly (favourite / shared route),
    // not from a nearby search. On exit we re-search at real GPS so we don't
    // strand the user on a remote origin.
    private var launchedStationActive = false
    private var consecutiveErrors = 0
    private var lastVibeTick = 0L
    private var loadedFromCache = false
    private var lastInteractionTime = now()
    private var timerJob: Job? = null

    // Settings quick-launch of a favourite: entered once the fetched departures
    // contain the matching line+destination (Garmin's mPendingFavTrack analog).
    private var pendingFavTrack: Pair<String, String>? = null

    // Phone location backfill + liveness (parity with the Apple watch's
    // reqLoc / loc flow and hello/alive/bye announcements).
    private var phoneLat: Double? = null
    private var phoneLon: Double? = null
    private var phoneLocTs = 0L
    private var lastLocRequestTs = 0L
    private var lastAliveSentTs = 0L

    private fun now(): Long = System.currentTimeMillis()
    private fun nowSeconds(): Long = now() / 1000

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
        wearSync.isWatch = true
        viewModelScope.launch { prefs.ensureFirstLaunchTimestamp() }
        viewModelScope.launch {
            defaultMode = prefs.defaultModeNow()
            currentMode = defaultMode
        }
        viewModelScope.launch { pendingRouteStore.pending.collect { pendingRoute = it } }
        viewModelScope.launch {
            prefs.defaultMode.collect {
                defaultMode = it
                wearSync.pushState()
            }
        }
        viewModelScope.launch {
            favouritesStore.favourites.collect {
                favouritesList = it
                favouriteDepartures = extractFavouritesFromCurrent(departures)
                wearSync.pushState()
            }
        }
        viewModelScope.launch {
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
        viewModelScope.launch {
            // Mirror commands relayed by WatchWearListenerService while the UI is up.
            WearCommandBus.events.collect { handlePhoneCommand(it) }
        }
    }

    // Action-dispatched phone -> watch contract, shared with the Apple and Garmin
    // watches. The watch stays standalone; these only apply an optional mirror.
    private fun handlePhoneCommand(cmd: WearCommand) {
        // Tracking is the end game: while tracking, the phone's navigation must
        // not pull the watch out. Only a fresh track command (a separate path)
        // switches what it tracks. Location still flows through as a GPS fallback.
        if (appState == 2 && cmd.action != "loc") return
        when (cmd.action) {
            "mode" -> cmd.mode?.let { setModeFromPhone(TransportMode.fromRaw(it)) }
            "station" -> showStationFromPhone(cmd)
            "loc" -> {
                val lat = cmd.lat
                val lon = cmd.lon
                if (lat != null && lon != null) onPhoneLocation(lat, lon)
            }
            "back" -> if (appState == 2) exitToStationView()
        }
    }

    // Phone switched mode. Reuse the standalone selectMode when the mode is already
    // loaded; otherwise switch and fetch fresh stations from the effective position.
    private fun setModeFromPhone(mode: TransportMode) {
        lastInteractionTime = now()
        if (appState == 3) resumeFromInactive()
        if (mode in availableModes) {
            selectMode(mode)
            return
        }
        currentMode = mode
        stationIndex = 0
        departures = emptyList()
        favouriteDepartures = emptyList()
        val coord = effectivePosition()
        if (coord != null && !requestInFlight) fetchStations(coord.lat, coord.lon)
    }

    // Phone selected a specific station. There's no nearby-search path for it,
    // so synthesise the station, show it as the sole entry, and fetch its departures.
    private fun showStationFromPhone(cmd: WearCommand) {
        val stId = cmd.stId ?: return
        launchStation(stId, cmd.name, cmd.lat, cmd.lon)
    }

    // Make a specific station the current one without a nearby search. Does NOT
    // touch appState or the departure list, the caller decides whether to show
    // the board or go straight to a countdown. Leaves lastSearchCoordinate at the
    // user's real GPS origin, not this station, a launched remote origin must not
    // become the watch's assumed position (the GPS-less walk/position fallback
    // reads it).
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

    // Show a specific station directly (phone mirror or settings quick launch),
    // the peer of Garmin's launchStation. Blanks the list to a spinner while the
    // board loads.
    fun launchStation(stId: String, name: String?, lat: Double? = null, lon: Double? = null) {
        setLaunchedStation(stId, name, lat, lon)
        appState = 0
        departures = emptyList()
        favouriteDepartures = emptyList()
        fetchDepartures(stId)
    }

    // Leave a launched station and return to the nearby list at the user's
    // real location. No-op when the current station came from a nearby search.
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
    }

    // Quick launch a favourite (settings), the peer of Garmin's
    // enterTrackingForFavourite: fetch its station and jump straight onto the
    // tracking bar once the matching departure arrives (tryEnterPendingFavTrack).
    fun launchFavourite(fav: Favourite) {
        pendingFavTrack = fav.lineNumber to fav.destination
        launchStation(fav.stationId, fav.stationName)
    }

    private fun tryEnterPendingFavTrack() {
        val (line, dest) = pendingFavTrack ?: return
        pendingFavTrack = null
        val match = departures.firstOrNull {
            it.lineNumber == line && it.destination == dest && !it.isGone
        } ?: return
        selectDepartureImpl(match)
    }

    // Phone location backfill

    private fun onPhoneLocation(lat: Double, lon: Double) {
        phoneLat = lat
        phoneLon = lon
        phoneLocTs = now()
        // Only act on it when our own GPS can't carry us. A good in-bounds fix stays primary.
        if (!gpsUsableInBounds()) searchFromPhoneLocation()
    }

    // Our own fix is present, accurate enough, and inside Switzerland.
    private fun gpsUsableInBounds(): Boolean {
        val coord = location.coordinate.value ?: return false
        val usable = gpsQuality == GpsQuality.GOOD || gpsQuality == GpsQuality.POOR
        return usable && SwissBounds.contains(coord.lat, coord.lon)
    }

    private fun phoneLocFresh(): Boolean = phoneLocTs > 0 && now() - phoneLocTs < 120_000

    // The coordinate to act on: a usable in-bounds GPS fix wins; otherwise a fresh
    // phone location; otherwise any GPS fix; otherwise the last search anchor.
    private fun effectivePosition(): LatLon? {
        if (gpsUsableInBounds()) return location.coordinate.value
        val lat = phoneLat
        val lon = phoneLon
        if (phoneLocFresh() && lat != null && lon != null) return LatLon(lat, lon)
        return location.coordinate.value ?: lastSearchCoordinate
    }

    private fun searchFromPhoneLocation() {
        val lat = phoneLat
        val lon = phoneLon
        if (appState > 1 || !phoneLocFresh() || lat == null || lon == null) return
        if (requestInFlight) return
        if (stations.isEmpty()) status = "Updating stations..."
        fetchStations(lat, lon)
    }

    // Ask the phone for its location when our GPS is weak. Throttled so we don't spam.
    private fun requestPhoneLocation() {
        if (now() - lastLocRequestTs < 30_000) return
        lastLocRequestTs = now()
        viewModelScope.launch { wearSync.sendLiveness(WearSync.KIND_REQ_LOC) }
    }

    // Lifecycle

    fun onAppear() {
        lastInteractionTime = now()
        viewModelScope.launch {
            location.start()
            if (location.loadedFromCache) loadedFromCache = true
        }
        startTimer(if (appState == 2) Timing.TRACKING_REFRESH_INTERVAL else Timing.NORMAL_REFRESH_INTERVAL)
        // Announce we're up so a listening phone greens its link indicator at once.
        viewModelScope.launch { wearSync.sendLiveness(WearSync.KIND_HELLO, livenessTracking()) }
    }

    fun onDisappear() {
        location.stop()
        stopTimer()
        // The heartbeat stops with the timer, so the phone ambers while we're
        // backgrounded, same semantics as the Apple watch's bye.
        viewModelScope.launch { wearSync.sendLiveness(WearSync.KIND_BYE) }
    }

    // The focused departure stamped onto hello/alive while tracking, so the
    // phone mirrors the tracking state from the heartbeat alone.
    private fun livenessTracking(): TrackCommand? {
        val focused = focusedTrain ?: return null
        if (appState != 2) return null
        return TrackCommand.from(focused, currentStation?.id)
    }

    fun onPermissionResult(granted: Boolean) {
        if (granted) onAppear() else location.onPermissionDenied()
    }

    // Chip tap / route-view resume of the current leg. An explicit tap always
    // opens the countdown, even hours out. A live board match gives real
    // delay/platform, otherwise a local countdown. Never re-queues.
    fun resumePendingRoute() {
        val route = pendingRoute ?: return
        launchTrackLeg(route) { it.cursor }
    }

    // Route-view "Track now" on any trackable leg (may jump ahead to a later
    // connection). Untrackable legs (walk / outside Switzerland) are ignored.
    fun trackLeg(index: Int) {
        val route = pendingRoute ?: return
        launchTrackLeg(route) { index }
    }

    // Route-view per-leg track/notify toggle. The pending route is phone-owned,
    // so there's no watch-side reminder to reschedule. The phone owns
    // notifications, so we just record the choice locally.
    fun setLegMuted(index: Int, muted: Boolean) {
        viewModelScope.launch { pendingRouteStore.setLegMuted(index, muted) }
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

    private fun launchTrackLeg(route: PendingRoute, indexOf: (PendingRoute) -> Int) {
        if (pendingResumeInFlight) return
        pendingResumeInFlight = true
        viewModelScope.launch {
            try {
                val normalized = PendingRouteLogic.normalize(route, nowSeconds()) ?: return@launch
                trackLegImpl(normalized, indexOf(normalized))
            } finally {
                pendingResumeInFlight = false
            }
        }
    }

    // Force-enter tracking for a trackable leg. The countdown is fully local
    // (derived from the leg's departure time), so enter it immediately: no board
    // fetch gates it, so a slow network can't delay the countdown. The origin
    // becomes the current station, so beginTracking's timer fetches that board in
    // the background and updateFocusedTrain upgrades platform/delay when the train
    // appears. Never re-queues.
    private fun trackLegImpl(route: PendingRoute, index: Int) {
        val leg = route.legs.getOrNull(index)?.takeIf { it.isTrackable } ?: return
        val stationId = leg.originId ?: return
        setLaunchedStation(stationId, leg.originName, leg.originLat, leg.originLon)
        enterProtectedTrack(leg)
    }

    // Track command from the phone (MessageClient): enter tracking directly.
    fun handleTrackCommand(cmd: TrackCommand) {
        beginTracking(cmd.toFocusedDeparture(), cmd.stationId)
    }

    // Track a shared-route leg whose train isn't on the live board yet. The
    // countdown is fully local (derived from depTs); updateFocusedTrain keeps
    // it until the train departs, then a live board match upgrades it with
    // real delay/platform.
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
            ),
            leg.originId,
        )
    }

    // Shared tracking entry: from a board tap, a phone track command, or a
    // synthesised shared-route leg. Everything downstream (timer cadence,
    // formation, foreground service) is identical once we have a FocusedDeparture.
    private fun beginTracking(focused: FocusedDeparture, formationStationId: String?) {
        focusedTrain = focused
        appState = 2
        location.setTrackingAccuracy(true)
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = 0
        formation = null

        // Reflect the same focused train on the phone (parity with the Garmin and
        // Apple watch trackStarted echoes — it doubles as the delivery ack).
        viewModelScope.launch {
            wearSync.sendLiveness(
                WearSync.KIND_TRACK_STARTED,
                TrackCommand.from(focused, currentStation?.id),
            )
        }
        val trainNumber = focused.trainNumber
        if (trainNumber != null && Formation.isRailCategory(focused.category) && formationStationId != null) {
            val date = formationDateString()
            viewModelScope.launch {
                formation = runCatching {
                    api.fetchFormation(trainNumber, date, formationStationId, focused.operatorRef)
                }.getOrNull()
            }
        }
        TrackingService.start(getApplication(), focused.destination)
        startTimer(Timing.TRACKING_REFRESH_INTERVAL)
        haptics.shortPulse()
    }

    // Ask the phone to save the focused departure as a reminder. Needs the origin
    // station's coords (the phone's distance-aware reminder is computed from them).
    fun remindOnPhone() {
        val focused = focusedTrain ?: return
        val station = currentStation
        val lat = station?.lat
        val lon = station?.lon
        if (station == null || lat == null || lon == null) {
            flashReminderStatus("No station location")
            return
        }
        val cmd = ReminderCommand(
            destination = focused.destination,
            departureTimestamp = focused.departureTimestamp,
            lineNumber = focused.lineNumber,
            trainNumber = focused.trainNumber,
            stationId = station.id,
            stationName = station.name ?: "Station",
            lat = lat,
            lon = lon,
        )
        viewModelScope.launch {
            val ok = wearSync.sendReminder(cmd)
            flashReminderStatus(if (ok) "Saved on phone" else "Open TrainTime on your phone")
        }
    }

    private fun flashReminderStatus(message: String) {
        reminderStatus = message
        viewModelScope.launch {
            delay(3000)
            reminderStatus = null
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

    private fun onLocationUpdate(coord: LatLon?) {
        gpsQuality = location.gpsQuality

        if (coord == null) {
            if (stations.isEmpty()) {
                status = "GPS: Searching..."
                // No usable watch GPS, lean on the phone if it offered a fix,
                // else ask it for one (throttled).
                if (!requestInFlight) {
                    if (phoneLocFresh()) searchFromPhoneLocation() else requestPhoneLocation()
                }
            }
            return
        }
        if (!SwissBounds.contains(coord.lat, coord.lon) && stations.isEmpty()) {
            status = "Not in Switzerland"
            return
        }
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

    private fun onTimerTick() {
        gpsQuality = location.gpsQuality

        // Heartbeat so the phone's link indicator stays green while we're open.
        // Same ≥7 s cadence as the Apple watch; stops with the timer on background.
        if (now() - lastAliveSentTs >= 7_000) {
            lastAliveSentTs = now()
            viewModelScope.launch { wearSync.sendLiveness(WearSync.KIND_ALIVE, livenessTracking()) }
        }

        val startTime = requestStartTime
        if (requestInFlight && startTime != null && now() - startTime > Timing.REQUEST_TIMEOUT * 1000) {
            requestInFlight = false
            requestStartTime = null
            if (appState == 2) consecutiveErrors += 1
        }

        val coord = location.coordinate.value ?: effectivePosition() ?: run {
            // No watch fix and no phone fallback yet, ask the phone (throttled).
            if (stations.isEmpty()) requestPhoneLocation()
            return
        }

        val lastSearch = lastSearchCoordinate
        if (appState <= 1 && lastSearch != null && location.hasMovedSignificantly(lastSearch)) {
            fetchStations(coord.lat, coord.lon)
            return
        }

        val stationLat = currentStation?.lat
        val stationLon = currentStation?.lon
        if (stationLat != null && stationLon != null) {
            lastWalkDist = GeoUtils.haversineDistance(coord.lat, coord.lon, stationLat, stationLon)
        }

        if (appState == 2) {
            val focused = focusedTrain
            if (focused != null) {
                val minutesLeft = focused.minutesUntil(nowSeconds())
                if (minutesLeft < -1.0) {
                    // Train long gone: go inactive like the Apple watch, so the
                    // next glance shows fresh data instead of a stale list.
                    haptics.shortPulse()
                    enterInactiveState()
                    return
                }
                val walkMin = GeoUtils.walkMinutes(lastWalkDist)
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

        if (appState == 0 && !subScreenOpen && now() - lastInteractionTime >= Timing.INACTIVITY_TIMEOUT * 1000) {
            enterInactiveState()
            return
        }
        if (appState == 3) return

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

    // Selection & tracking

    fun selectDeparture(index: Int) {
        departures.getOrNull(index)?.let { selectDepartureImpl(it) }
    }

    // Favourite rows in the top block carry a Departure directly.
    fun selectDeparture(departure: Departure) = selectDepartureImpl(departure)

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
            ),
            currentStation?.id,
        )

        // Only user-initiated tracking counts toward the review ask; a
        // phone-pushed track command in handleTrackCommand doesn't.
        viewModelScope.launch {
            prefs.incrementReviewTrackCount()
            maybeShowReviewPrompt()
        }
    }

    private suspend fun maybeShowReviewPrompt() {
        val should = ReviewGate.shouldPrompt(
            trackCount = prefs.reviewTrackCount.first(),
            promptedVersion = prefs.reviewPromptedVersion.first(),
            currentVersion = BuildConfig.VERSION_NAME,
            firstLaunchTs = prefs.firstLaunchTs.first(),
            snoozeUntil = prefs.reviewSnoozeUntil.first(),
            optedOut = prefs.reviewOptOut.first(),
            now = now(),
        )
        if (should) {
            // Shown counts as asked for this version, whatever button follows.
            prefs.setReviewPromptedVersion(BuildConfig.VERSION_NAME)
            showReviewPrompt = true
        }
    }

    fun dismissReviewPrompt() {
        showReviewPrompt = false
    }

    // Refresh the settings "Phone" row (a connected node is the paired phone).
    fun refreshPhoneLink() {
        viewModelScope.launch { phoneConnected = wearSync.connectedWatchNames().isNotEmpty() }
    }

    fun snoozeReview() {
        showReviewPrompt = false
        viewModelScope.launch { prefs.setReviewSnoozeUntil(now() + ReviewGate.SNOOZE_MS) }
    }

    fun optOutReview() {
        showReviewPrompt = false
        viewModelScope.launch { prefs.setReviewOptOut(true) }
    }

    fun enterInactiveState() {
        if (appState == 2) {
            viewModelScope.launch { wearSync.sendLiveness(WearSync.KIND_TRACK_ENDED) }
        }
        appState = 3
        location.setTrackingAccuracy(false)
        focusedTrain = null
        formation = null
        consecutiveErrors = 0
        TrackingService.stop(getApplication())
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
    }

    fun resumeFromInactive() {
        lastInteractionTime = now()
        appState = 0
    }

    // Paused-screen resume (terminal user action, no launch follows), so it can
    // safely re-search: a launched route that timed out into inactive returns
    // to the user's real location instead of the remote origin board.
    fun resumeToStationView() {
        resumeFromInactive()
        returnToNearbyIfLaunched()
    }

    fun noteInteraction() {
        lastInteractionTime = now()
    }

    fun updateDefaultMode(mode: TransportMode) {
        defaultMode = mode
        viewModelScope.launch { prefs.setDefaultMode(mode) }
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
        lastInteractionTime = now()
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

    fun exitToStationView() {
        if (appState == 2) {
            viewModelScope.launch { wearSync.sendLiveness(WearSync.KIND_TRACK_ENDED) }
        }
        lastInteractionTime = now()
        appState = 0
        location.setTrackingAccuracy(false)
        focusedTrain = null
        formation = null
        consecutiveErrors = 0
        TrackingService.stop(getApplication())
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
        // A shared/favourite route launched a remote origin, return to the
        // nearby list at the user's real location, not that origin.
        returnToNearbyIfLaunched()
    }

    // Mode / station navigation

    fun selectMode(mode: TransportMode) {
        lastInteractionTime = now()
        if (mode == currentMode) return
        currentMode = mode
        stationIndex = 0
        adoptEmbeddedOrFetch()
    }

    fun selectStation(index: Int) {
        lastInteractionTime = now()
        if (index < 0 || index >= stations.size) return
        stationIndex = index
        adoptEmbeddedOrFetch()
    }

    private fun adoptEmbeddedOrFetch() {
        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            viewModelScope.launch { favouriteDepartures = extractFavouritesFromCurrent(deps) }
            lastFetchTime = now()
        } else {
            // Keep the previous list (greyed via departuresRefreshing) until the
            // new board arrives, rather than blanking to a spinner.
            currentStation?.let { fetchDepartures(it.id) }
        }
    }

    fun isStationPinned(id: String): Boolean = id in pinnedStationIds

    fun togglePinnedStation(station: Station) {
        lastInteractionTime = now()
        viewModelScope.launch { myStationsStore.toggle(station) }
    }

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
                if (modes.contains(defaultMode)) currentMode = defaultMode
                else modes.firstOrNull()?.let { currentMode = it }
            }
            stationIndex = 0
        }

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
    }

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
            // opened early, before it reaches the horizon). Keep the local
            // countdown; only give up once it has actually departed.
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
            return focused.minutesUntil(nowSeconds()) - GeoUtils.walkMinutes(lastWalkDist)
        }

    val trackingEffectiveBuffer: Double
        get() {
            val focused = focusedTrain ?: return 0.0
            return trackingScheduledBuffer + focused.delay.toDouble()
        }

    val trackingStatusText: String
        get() {
            val buf = trackingEffectiveBuffer
            // Cached coordinates prove nothing about where we are now; no verdict.
            if (gpsQuality == GpsQuality.UNAVAILABLE || gpsQuality == GpsQuality.LAST_KNOWN) return "No GPS"
            val absBuf = kotlin.math.abs(buf)
            if (absBuf < 0.5) return "On time"
            val unit = if (absBuf < 1.5) "${(absBuf * 60).toInt()}s" else "${absBuf.toInt()} min"
            return if (buf > 0) "$unit ahead" else "$unit behind"
        }

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
    // existing list rather than blanking it, so a refresh freezes the board in
    // place instead of hiding it behind a spinner.
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
            tryEnterPendingFavTrack()
        } catch (e: Exception) {
            requestInFlight = false
            requestStartTime = null
            departuresRefreshing = false
            pendingFavTrack = null
            handleError(e, "Departures")
        }
    }

    suspend fun forceRefresh() {
        lastInteractionTime = now()
        var waited = 0
        while (requestInFlight && waited < 100) {
            delay(100)
            waited += 1
        }
        val id = currentStation?.id ?: return
        fetchDeparturesAsync(id)
    }

    private fun handleError(error: Exception, context: String) {
        if (appState == 2) {
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

    private fun formationDateString(): String =
        LocalDate.now(ZoneId.of("Europe/Zurich")).toString()

    private suspend fun extractFavouritesFromCurrent(deps: List<Departure>): List<Departure> {
        val stationId = currentStation?.id ?: return emptyList()
        return favouritesStore.extractFavourites(deps, stationId)
    }
}

// The next ride leg while tracking a shared route: where the user changes, the
// onward train, and the connection buffer in minutes.
data class OnwardConnection(
    val changeStation: String,
    val leg: RouteLeg,
    val legIndex: Int,
    val changeMinutes: Long,
)
