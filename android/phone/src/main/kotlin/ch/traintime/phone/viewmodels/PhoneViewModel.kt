package ch.traintime.phone.viewmodels

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import ch.traintime.shared.*
import ch.traintime.shared.api.TrainAPIService
import ch.traintime.shared.geo.GeoUtils
import ch.traintime.shared.models.*
import ch.traintime.phone.services.ConnectedWatch
import ch.traintime.phone.services.HapticService
import ch.traintime.phone.services.LocationService
import ch.traintime.phone.services.WatchService
import kotlinx.coroutines.*

class PhoneViewModel(application: Application) : AndroidViewModel(application) {
    // Services
    val locationService = LocationService(application)
    private val hapticService = HapticService(application)
    val watchService = WatchService(application)

    // App State
    var appState by mutableIntStateOf(0)
        private set
    var status by mutableStateOf("GPS: Searching...")
        private set

    // Station Data
    var trainStations by mutableStateOf<List<Station>>(emptyList())
        private set
    var busStations by mutableStateOf<List<Station>>(emptyList())
        private set
    var tramStations by mutableStateOf<List<Station>>(emptyList())
        private set
    var specialStations by mutableStateOf<List<Station>>(emptyList())
        private set
    var stationIndex by mutableIntStateOf(0)
        private set

    // Transport Modes
    var currentMode by mutableStateOf(TransportMode.TRAIN)
        private set
    var defaultMode by mutableStateOf(TransportMode.TRAIN)
        private set
    var availableModes by mutableStateOf<List<TransportMode>>(emptyList())
        private set

    // Departures
    var departures by mutableStateOf<List<Departure>>(emptyList())
        private set

    // Selection & Tracking
    var showStationPicker by mutableStateOf(false)
    var focusedTrain by mutableStateOf<FocusedDeparture?>(null)
        private set

    // GPS
    var gpsQuality by mutableStateOf(GPSQuality.UNAVAILABLE)
        private set
    var lastWalkDist by mutableDoubleStateOf(0.0)
        private set
    var lastWalkTime: Double? by mutableStateOf(null)
        private set

    // Watch connectivity
    var connectedWatches by mutableStateOf<List<ConnectedWatch>>(emptyList())
        private set
    var watchSendStatus by mutableStateOf<String?>(null)
        private set

    // Internal
    private var requestInFlight = false
    private var requestStartTime: Long? = null
    private var lastFetchTime: Long = 0L
    private var lastSearchLat: Double? = null
    private var lastSearchLon: Double? = null
    private var consecutiveErrors = 0
    private var lastVibeTick: Long = 0L
    private var loadedFromCache = false
    private var timerJob: Job? = null
    private var pendingDeepLink: Uri? = null
    private var lastInteractionTime: Long = System.currentTimeMillis()

    init {
        // If location was loaded from cache, mark it
        if (locationService.location != null && locationService.location?.accuracy == -1f) {
            loadedFromCache = true
        }

        // Load default mode
        val prefs = application.getSharedPreferences("traintime", Context.MODE_PRIVATE)
        val savedMode = prefs.getInt("defaultMode", 0)
        val mode = TransportMode.entries.getOrNull(savedMode) ?: TransportMode.TRAIN
        defaultMode = mode
        currentMode = mode
    }

    // Computed
    val stations: List<Station>
        get() = when (currentMode) {
            TransportMode.TRAIN -> trainStations
            TransportMode.BUS -> busStations
            TransportMode.TRAM -> tramStations
            TransportMode.SPECIAL -> specialStations
        }

    val currentStation: Station?
        get() {
            val s = stations
            return if (s.isNotEmpty() && stationIndex < s.size) s[stationIndex] else null
        }

    val walkInfo: String
        get() {
            val station = currentStation ?: return ""
            return station.walkInfo(stationIndex, stations.size)
        }

    val stationName: String
        get() = currentStation?.name ?: "Station"

    // Tracking calculations
    val trackingScheduledBuffer: Double
        get() {
            val focused = focusedTrain ?: return 0.0
            val walkMin = lastWalkTime?.let { it / 60.0 } ?: GeoUtils.walkMinutes(lastWalkDist)
            return focused.minutesUntil - walkMin
        }

    val trackingEffectiveBuffer: Double
        get() {
            val focused = focusedTrain ?: return 0.0
            return trackingScheduledBuffer + focused.delay.toDouble()
        }

    val trackingStatusText: String
        get() {
            val buf = trackingEffectiveBuffer
            if (gpsQuality == GPSQuality.UNAVAILABLE) return "No GPS"
            val absBuf = kotlin.math.abs(buf)
            if (absBuf < 0.5) return "On time"
            val unit = if (absBuf < 1.5) "${(absBuf * 60).toInt()}s" else "${absBuf.toInt()} min"
            return if (buf > 0) "$unit ahead" else "$unit behind"
        }

    val trackingStatusColorInt: Int
        get() {
            val buf = trackingEffectiveBuffer
            if (gpsQuality == GPSQuality.UNAVAILABLE) return AppColors.BAR_GRAY
            if (buf > 0.5) return AppColors.AHEAD
            if (buf < -0.5) return AppColors.BEHIND
            return AppColors.ON_TIME
        }

    val directionToStation: Double?
        get() {
            val loc = locationService.location ?: return null
            val station = currentStation ?: return null
            val stationLat = station.lat ?: return null
            val stationLon = station.lon ?: return null
            val heading = locationService.heading ?: return null
            val bearing = GeoUtils.bearing(loc.latitude, loc.longitude, stationLat, stationLon)
            return (bearing - heading) * 180.0 / Math.PI
        }

    // Lifecycle
    fun onPermissionGranted() {
        locationService.start()
    }

    fun onAppear() {
        lastInteractionTime = System.currentTimeMillis()
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
        watchService.initialize()
        viewModelScope.launch {
            locationService.locationFlow.collect { location ->
                onLocationUpdate(location)
            }
        }
    }

    fun onDisappear() {
        locationService.stop()
        timerJob?.cancel()
        watchService.shutdown()
    }

    private fun startTimer(intervalMs: Long) {
        timerJob?.cancel()
        timerJob = viewModelScope.launch {
            while (isActive) {
                delay(intervalMs)
                onTimerTick()
            }
        }
    }

    private fun onLocationUpdate(location: android.location.Location?) {
        gpsQuality = GPSQuality.from(location?.accuracy)

        if (location == null) {
            if (stations.isEmpty()) status = "GPS: Searching..."
            return
        }

        if (!SwissBounds.contains(location.latitude, location.longitude) && stations.isEmpty()) {
            status = "Not in Switzerland"
            return
        }

        // Skip station search in tracking/inactive (still update GPS above)
        if (appState >= 2) return

        // When transitioning from cached to live GPS, re-fetch if moved
        if (loadedFromCache && (gpsQuality == GPSQuality.GOOD || gpsQuality == GPSQuality.POOR)) {
            loadedFromCache = false
            val lastLat = lastSearchLat
            val lastLon = lastSearchLon
            if (lastLat != null && lastLon != null &&
                GeoUtils.hasMovedSignificantly(lastLat, lastLon, location.latitude, location.longitude)) {
                clearStationState()
            }
            if (!requestInFlight) {
                status = "Updating stations..."
                fetchStations(location.latitude, location.longitude)
            }
            return
        }

        if (stations.isEmpty() && !requestInFlight) {
            status = "Finding stations..."
            fetchStations(location.latitude, location.longitude)
        }
    }

    private fun onTimerTick() {
        val location = locationService.location
        gpsQuality = GPSQuality.from(location?.accuracy)

        // Request timeout
        if (requestInFlight) {
            val startTime = requestStartTime
            if (startTime != null && System.currentTimeMillis() - startTime > Timing.REQUEST_TIMEOUT) {
                requestInFlight = false
                requestStartTime = null
                if (appState == 2) {
                    consecutiveErrors++
                }
            }
        }

        if (location == null) return

        // Movement detection (only in station/selection view)
        val lastLat = lastSearchLat
        val lastLon = lastSearchLon
        if (appState <= 1 && lastLat != null && lastLon != null &&
            GeoUtils.hasMovedSignificantly(lastLat, lastLon, location.latitude, location.longitude)) {
            clearStationState()
            fetchStations(location.latitude, location.longitude)
            return
        }

        // Update walk distance
        val station = currentStation
        val stLat = station?.lat
        val stLon = station?.lon
        if (station != null && stLat != null && stLon != null) {
            val haversine = GeoUtils.haversineDistance(
                location.latitude, location.longitude, stLat, stLon
            )
            lastWalkDist = haversine
            lastWalkTime = null
        }

        // State 2: auto-exit + heartbeat
        if (appState == 2) {
            val focused = focusedTrain
            if (focused != null) {
                val minutesLeft = focused.minutesUntil
                if (minutesLeft < -1.0) {
                    hapticService.shortPulse()
                    enterInactiveState()
                    return
                }

                val walkMin = lastWalkTime?.let { it / 60.0 } ?: GeoUtils.walkMinutes(lastWalkDist)
                val effectBuf = minutesLeft - walkMin + focused.delay.toDouble()
                if (effectBuf < -0.5) {
                    val now = System.currentTimeMillis() / 1000
                    val interval = if (effectBuf < -2.0) 2 else 4
                    if (now - lastVibeTick >= interval) {
                        hapticService.heartbeat()
                        lastVibeTick = now
                    }
                }
            }
        }

        // Inactivity timeout in station view
        if (appState == 0 && System.currentTimeMillis() - lastInteractionTime >= Timing.INACTIVITY_TIMEOUT) {
            enterInactiveState()
            return
        }

        if (appState == 3) return

        // Fetch departures on cooldown
        val cooldown = if (appState == 2) Timing.FETCH_COOLDOWN_TRACKING else Timing.FETCH_COOLDOWN_NORMAL
        if (!requestInFlight && System.currentTimeMillis() - lastFetchTime >= cooldown) {
            val s = currentStation
            if (s != null && s.id != null) {
                fetchDepartures(s.id!!)
            } else if (stations.isEmpty()) {
                fetchStations(location.latitude, location.longitude)
            }
        }
    }

    // Departure selection & tracking
    fun selectDeparture(index: Int) {
        if (index < 0 || index >= departures.size) return
        val dep = departures[index]
        val depTs = dep.departureTimestamp ?: return
        if (dep.isGone) return

        focusedTrain = FocusedDeparture(
            destination = dep.destination,
            departureTimestamp = depTs,
            lineNumber = dep.lineNumber,
            delay = dep.delay,
            platform = dep.platform,
            platformChanged = dep.platformChanged
        )
        appState = 2
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = 0

        startTimer(Timing.TRACKING_REFRESH_INTERVAL)
        hapticService.shortPulse()
    }

    fun enterInactiveState() {
        appState = 3
        focusedTrain = null
        consecutiveErrors = 0
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
    }

    fun resumeFromInactive() {
        lastInteractionTime = System.currentTimeMillis()
        appState = 0
    }

    fun exitToStationView() {
        lastInteractionTime = System.currentTimeMillis()
        appState = 0
        focusedTrain = null
        consecutiveErrors = 0
        startTimer(Timing.NORMAL_REFRESH_INTERVAL)
    }

    fun updateDefaultMode(mode: TransportMode) {
        defaultMode = mode
        getApplication<Application>().getSharedPreferences("traintime", Context.MODE_PRIVATE)
            .edit().putInt("defaultMode", mode.ordinal).apply()
    }

    // Mode navigation
    fun selectMode(mode: TransportMode) {
        lastInteractionTime = System.currentTimeMillis()
        if (mode == currentMode) return
        currentMode = mode
        stationIndex = 0

        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            lastFetchTime = System.currentTimeMillis()
        } else {
            departures = emptyList()
            currentStation?.id?.let { fetchDepartures(it) }
        }
    }

    fun selectStation(index: Int) {
        lastInteractionTime = System.currentTimeMillis()
        if (index < 0 || index >= stations.size) return
        stationIndex = index
        showStationPicker = false

        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            lastFetchTime = System.currentTimeMillis()
        } else {
            departures = emptyList()
            currentStation?.id?.let { fetchDepartures(it) }
        }
    }

    private fun rebuildModesAndSelect() {
        val modes = mutableListOf<TransportMode>()
        if (trainStations.isNotEmpty()) modes.add(TransportMode.TRAIN)
        if (busStations.isNotEmpty()) modes.add(TransportMode.BUS)
        if (tramStations.isNotEmpty()) modes.add(TransportMode.TRAM)
        if (specialStations.isNotEmpty()) modes.add(TransportMode.SPECIAL)
        availableModes = modes

        if (stations.isEmpty() && modes.isNotEmpty()) {
            currentMode = if (defaultMode in modes) defaultMode else modes.first()
        }

        stationIndex = 0

        val deps = currentStation?.embeddedDepartures
        if (!deps.isNullOrEmpty()) {
            departures = deps
            lastFetchTime = System.currentTimeMillis()
        } else {
            departures = emptyList()
            currentStation?.id?.let { fetchDepartures(it) }
        }

        pendingDeepLink?.let { uri ->
            pendingDeepLink = null
            handleDeepLink(uri)
        }
    }

    private fun clearStationState() {
        trainStations = emptyList()
        busStations = emptyList()
        tramStations = emptyList()
        specialStations = emptyList()
        stationIndex = 0
        departures = emptyList()
        availableModes = emptyList()
        consecutiveErrors = 0
        if (appState == 2) exitToStationView()
        status = "Finding stations..."
    }

    private fun updateFocusedTrain() {
        val focused = focusedTrain ?: return

        val matches = departures.filter {
            it.destination == focused.destination && it.minutesUntil >= -1
        }
        val best = matches.minByOrNull {
            kotlin.math.abs(it.minutesUntil.toDouble() - focused.minutesUntil)
        }
        if (best == null) {
            hapticService.shortPulse()
            enterInactiveState()
            return
        }

        val updated = focused.copy()
        if (best.platform != focused.platform && best.platform.isNotEmpty()) {
            if (best.platformChanged) {
                hapticService.platformChange()
            }
            updated.platform = best.platform
            updated.platformChanged = best.platformChanged
        }
        updated.delay = best.delay
        focusedTrain = updated
    }

    // API calls
    private fun fetchStations(lat: Double, lon: Double) {
        if (requestInFlight) return
        requestInFlight = true
        requestStartTime = System.currentTimeMillis()

        viewModelScope.launch {
            try {
                val result = TrainAPIService.fetchStations(lat, lon, defaultMode)
                trainStations = result.train
                busStations = result.bus
                tramStations = result.tram
                specialStations = result.special
                lastSearchLat = lat
                lastSearchLon = lon
                locationService.saveLastKnown()
                rebuildModesAndSelect()
                if (stations.isEmpty()) status = "No stations nearby"
            } catch (e: Exception) {
                handleError(e, "Stations")
            } finally {
                requestInFlight = false
                requestStartTime = null
            }
        }
    }

    private fun fetchDepartures(stationId: String) {
        if (requestInFlight) return
        requestInFlight = true
        requestStartTime = System.currentTimeMillis()

        viewModelScope.launch {
            try {
                val result = TrainAPIService.fetchDepartures(stationId)
                lastFetchTime = System.currentTimeMillis()
                consecutiveErrors = 0
                departures = result
                if (appState == 2) updateFocusedTrain()
            } catch (e: Exception) {
                handleError(e, "Departures")
            } finally {
                requestInFlight = false
                requestStartTime = null
            }
        }
    }

    private fun handleError(error: Exception, context: String) {
        if (appState == 2) {
            // In tracking mode: keep existing data, continue countdown
            consecutiveErrors++
            return
        }

        status = when (error) {
            is ch.traintime.shared.api.TrainAPIError.RateLimited -> "Rate limited"
            is ch.traintime.shared.api.TrainAPIError.HttpError -> "$context: ${error.code}"
            is ch.traintime.shared.api.TrainAPIError.NoData -> "$context error"
            is ch.traintime.shared.api.TrainAPIError.NetworkError -> "No connection"
            else -> "$context error"
        }
        departures = emptyList()
    }

    fun refreshConnectedWatches() {
        viewModelScope.launch {
            connectedWatches = watchService.getConnectedWatches()
        }
    }

    fun sendToWatch(watch: ConnectedWatch) {
        val focused = focusedTrain ?: return
        val stationId = currentStation?.id
        viewModelScope.launch {
            val success = watchService.sendTrackCommand(watch, focused, stationId)
            watchSendStatus = if (success) "Sent to ${watch.name}" else "Failed to send"
            // Auto-clear status after 3 seconds
            delay(3000)
            watchSendStatus = null
        }
    }

    fun sendToWatch() {
        // Convenience: send to first connected watch
        val watch = connectedWatches.firstOrNull()
        if (watch != null) {
            sendToWatch(watch)
        } else {
            watchSendStatus = "No watch connected"
            viewModelScope.launch {
                delay(3000)
                watchSendStatus = null
            }
        }
    }

    fun handleDeepLink(uri: Uri) {
        lastInteractionTime = System.currentTimeMillis()
        if (uri.scheme != "traintime" || uri.host != "track") return
        val destination = uri.getQueryParameter("destination") ?: return
        val timestamp = uri.getQueryParameter("timestamp")?.toIntOrNull() ?: return

        if (departures.isEmpty()) {
            pendingDeepLink = uri
            return
        }

        val index = departures.indexOfFirst {
            it.destination == destination && it.departureTimestamp == timestamp
        }
        if (index >= 0) selectDeparture(index)
    }

    class Factory(private val application: Application) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return PhoneViewModel(application) as T
        }
    }
}
