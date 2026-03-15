import SwiftUI
import CoreLocation
import Combine
import WatchKit

class TrainTimeViewModel: ObservableObject {
    // MARK: - Services
    let location = LocationService()
    private var locationCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var extendedSession: WKExtendedRuntimeSession?

    // MARK: - App State
    @Published var appState: Int = 0 // 0=station view, 2=focused tracking, 3=inactive
    @Published var status: String = "GPS: Searching..."

    // MARK: - Station Data (per mode)
    @Published var trainStations: [Station] = []
    @Published var busStations: [Station] = []
    @Published var tramStations: [Station] = []
    @Published var specialStations: [Station] = []
    @Published var stationIndex: Int = 0

    // MARK: - Transport Modes
    @Published var currentMode: TransportMode = .train
    @Published var availableModes: [TransportMode] = []

    // MARK: - Departures
    @Published var departures: [Departure] = []

    // MARK: - Selection & Tracking
    @Published var showStationPicker = false
    @Published var focusedTrain: FocusedDeparture? = nil

    // MARK: - GPS
    @Published var gpsQuality: GPSQuality = .unavailable
    @Published var lastWalkDist: Double = 0
    @Published var lastWalkTime: Double? = nil

    // MARK: - Internal State
    let routing = RoutingService.shared
    private var requestInFlight = false
    private var requestStartTime: Date?
    var lastFetchTime: Date = .distantPast
    private var lastSearchCoordinate: CLLocationCoordinate2D?
    var consecutiveErrors: Int = 0
    private var lastVibeTick: Int = 0
    private var tickCount: Int = 0
    private var loadedFromCache = false
    var lastInteractionTime: Date = Date()

    // MARK: - Computed

    var stations: [Station] {
        switch currentMode {
        case .train: return trainStations
        case .bus: return busStations
        case .tram: return tramStations
        case .special: return specialStations
        }
    }

    var currentStation: Station? {
        let s = stations
        guard !s.isEmpty, stationIndex < s.count else { return nil }
        return s[stationIndex]
    }

    var walkInfo: String {
        guard let station = currentStation else { return "" }
        return station.walkInfo(index: stationIndex, total: stations.count)
    }

    var stationName: String {
        currentStation?.name ?? "Station"
    }

    // MARK: - Init

    init() {
        // If we loaded a cached coordinate, mark it
        if location.coordinate != nil && location.horizontalAccuracy == -1 {
            loadedFromCache = true
        }

        locationCancellable = location.$coordinate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                self?.onLocationUpdate(coord)
            }
    }

    // MARK: - Lifecycle

    func onAppear() {
        lastInteractionTime = Date()
        location.start()
        startTimer(interval: Timing.normalRefreshInterval)
    }

    func onDisappear() {
        location.stop()
        stopTimer()
        endExtendedSession()
    }

    // MARK: - Timer

    private func startTimer(interval: TimeInterval) {
        stopTimer()
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.onTimerTick() }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Extended Runtime Session (keeps tracking alive when wrist drops)

    private func startExtendedSession() {
        guard extendedSession == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.start()
        extendedSession = session
    }

    private func endExtendedSession() {
        extendedSession?.invalidate()
        extendedSession = nil
    }

    // MARK: - Location Update

    private func onLocationUpdate(_ coord: CLLocationCoordinate2D?) {
        gpsQuality = location.gpsQuality

        guard let coord = coord else {
            if stations.isEmpty {
                status = "GPS: Searching..."
            }
            return
        }

        // Only gate initial search on Swiss bounds (border hysteresis)
        guard SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) || !stations.isEmpty else {
            if stations.isEmpty {
                status = "Not in Switzerland"
            }
            return
        }

        // If loaded from stale cache and now have a live GPS fix, re-search
        if loadedFromCache, location.gpsQuality == .good || location.gpsQuality == .poor {
            loadedFromCache = false
            if let lastSearch = lastSearchCoordinate,
               location.hasMovedSignificantly(from: lastSearch) {
                clearStationState()
            }
            if !requestInFlight {
                status = "Updating stations..."
                fetchStations(lat: coord.latitude, lon: coord.longitude)
            }
            return
        }

        if stations.isEmpty && !requestInFlight {
            status = "Finding stations..."
            fetchStations(lat: coord.latitude, lon: coord.longitude)
        }
    }

    // MARK: - Timer Tick

    private func onTimerTick() {
        tickCount += 1
        gpsQuality = location.gpsQuality

        // Request timeout check
        if requestInFlight, let startTime = requestStartTime,
           Date().timeIntervalSince(startTime) > Timing.requestTimeout {
            requestInFlight = false
            requestStartTime = nil
            if appState == 2 {
                consecutiveErrors += 1
                if consecutiveErrors >= Thresholds.consecutiveErrorLimit {
                    exitToStationView()
                }
            }
        }

        guard let coord = location.coordinate else { return }

        // Movement detection
        if let lastSearch = lastSearchCoordinate,
           location.hasMovedSignificantly(from: lastSearch) {
            clearStationState()
            fetchStations(lat: coord.latitude, lon: coord.longitude)
            return
        }

        // Update walk distance to current station
        if let station = currentStation, let stationCoord = station.coordinate {
            let haversine = GeoUtils.haversineDistance(from: coord, to: stationCoord)
            lastWalkDist = haversine
            lastWalkTime = nil

            if let stationId = station.id {
                if let interpolated = routing.interpolate(stationId: stationId, currentHaversine: haversine) {
                    lastWalkDist = interpolated.distance
                    lastWalkTime = interpolated.time
                }
                if routing.shouldRefetch(stationId: stationId, currentCoord: coord, currentHaversine: haversine) {
                    Task {
                        await routing.fetchRoute(from: coord, to: stationCoord, stationId: stationId, currentHaversine: haversine)
                    }
                }
            }
        }

        // State 2: auto-exit check and heartbeat
        if appState == 2 {
            if let focused = focusedTrain {
                let minutesLeft = focused.minutesUntil
                if minutesLeft < -1.0 {
                    HapticService.shortPulse()
                    enterInactiveState()
                    return
                }

                // Heartbeat when behind schedule (effective buffer includes delay)
                let walkMin = lastWalkTime.map { $0 / 60.0 } ?? GeoUtils.walkMinutes(distanceMeters: lastWalkDist)
                let delay = Double(focused.delay)
                let effectBuf = minutesLeft - walkMin + delay
                if effectBuf < -0.5 {
                    let now = Int(Date().timeIntervalSince1970)
                    let interval = effectBuf < -2.0 ? 2 : 4
                    if now - lastVibeTick >= interval {
                        HapticService.heartbeat()
                        lastVibeTick = now
                    }
                }
            }
        }

        // Inactivity timeout in station view
        if appState == 0, Date().timeIntervalSince(lastInteractionTime) >= Timing.inactivityTimeout {
            enterInactiveState()
            return
        }

        // Skip API fetches in inactive state
        if appState == 3 { return }

        // Fetch departures if cooldown elapsed
        if !requestInFlight,
           Date().timeIntervalSince(lastFetchTime) >= (appState == 2 ? Timing.fetchCooldownTracking : Timing.fetchCooldownNormal) {
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            } else if !stations.isEmpty {
                // No valid station selected
            } else {
                fetchStations(lat: coord.latitude, lon: coord.longitude)
            }
        }
    }

    // MARK: - Departure Selection & Tracking

    func selectDeparture(index: Int) {
        guard index >= 0, index < departures.count else { return }
        let dep = departures[index]
        guard let depTs = dep.departureTimestamp, !dep.isGone else { return }

        focusedTrain = FocusedDeparture(
            destination: dep.destination,
            departureTimestamp: depTs,
            delay: dep.delay,
            platform: dep.platform,
            platformChanged: dep.platformChanged
        )
        appState = 2
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = .distantPast  // Force immediate fetch on tracking entry

        // Switch to faster timer for tracking
        startTimer(interval: Timing.trackingRefreshInterval)
        startExtendedSession()
        HapticService.shortPulse()
    }

    func enterInactiveState() {
        appState = 3
        focusedTrain = nil
        consecutiveErrors = 0
        startTimer(interval: Timing.normalRefreshInterval)
        endExtendedSession()
    }

    func resumeFromInactive() {
        lastInteractionTime = Date()
        appState = 0
    }

    func exitToStationView() {
        lastInteractionTime = Date()
        appState = 0
        focusedTrain = nil
        consecutiveErrors = 0

        // Restore normal timer
        startTimer(interval: Timing.normalRefreshInterval)
        endExtendedSession()
    }

    // MARK: - API Calls

    private func fetchStations(lat: Double, lon: Double) {
        guard !requestInFlight else { return }
        requestInFlight = true
        requestStartTime = Date()

        Task {
            do {
                let result = try await TrainAPIService.fetchStations(lat: lat, lon: lon)
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    trainStations = result.train
                    busStations = result.bus
                    tramStations = result.tram
                    specialStations = result.special
                    lastSearchCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    location.saveLastKnownCoordinate()
                    rebuildModesAndSelect()

                    if stations.isEmpty {
                        status = "No stations nearby"
                    }
                }
            } catch {
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    handleError(error, context: "Stations")
                }
            }
        }
    }

    func fetchDepartures(stationId: String) {
        guard !requestInFlight else { return }
        requestInFlight = true
        requestStartTime = Date()

        Task {
            do {
                let result = try await TrainAPIService.fetchDepartures(stationId: stationId)
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    lastFetchTime = Date()
                    consecutiveErrors = 0
                    departures = result

                    // Update focused train if tracking
                    if appState == 2 {
                        updateFocusedTrain()
                    }
                }
            } catch {
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    handleError(error, context: "Departures")
                }
            }
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error, context: String) {
        if appState == 2 {
            // In tracking mode: tolerate errors with stale data
            consecutiveErrors += 1
            if consecutiveErrors >= Thresholds.consecutiveErrorLimit {
                exitToStationView()
                status = "Connection lost"
            }
            // Keep stale data for < 3 errors
            return
        }

        // In station view: clear and show error
        if let apiError = error as? TrainAPIError {
            switch apiError {
            case .rateLimited:
                status = "Rate limited"
            case .httpError(let code):
                status = "\(context): \(code)"
            case .noData:
                status = "\(context) error"
            case .networkError:
                status = "No connection"
            }
        } else {
            status = "\(context) error"
        }
        departures = []
    }

}
