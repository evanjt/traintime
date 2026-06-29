import SwiftUI
import CoreLocation
import Combine
import WatchKit
import WatchConnectivity

class TrainTimeViewModel: NSObject, ObservableObject, WCSessionDelegate {
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
    @Published var defaultMode: TransportMode = .train

    // MARK: - Departures
    @Published var departures: [Departure] = []
    @Published var favouriteDepartures: [Departure] = []

    // MARK: - Favourites
    let favouritesStore = FavouritesStore.shared

    // MARK: - Selection & Tracking
    @Published var showStationPicker = false
    @Published var focusedTrain: FocusedDeparture? = nil
    @Published var formation: Formation? = nil

    // MARK: - GPS
    @Published var gpsQuality: GPSQuality = .unavailable
    @Published var lastWalkDist: Double = 0
    @Published var lastWalkTime: Double? = nil
    @Published var useRoutedDistance: Bool = UserDefaults.standard.bool(forKey: "useRoutedDistance")

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

    // Phone location backfill (optional overlay). The phone pushes its coordinate as a GPS
    // fallback; we only use it when our own fix is unusable or out of Switzerland, never to
    // override a good in-bounds fix. Peer of the Garmin watch's mPhoneLat/mPhoneLon.
    private var phoneLat: Double?
    private var phoneLon: Double?
    private var phoneLocTs: Date?
    private var lastLocRequestTs: Date?
    // Liveness heartbeat throttle (announce alive to the phone every ≥7 s while reachable).
    private var lastAliveTsSec: Int = 0

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

    override init() {
        super.init()

        // Load default mode from UserDefaults
        if let savedRaw = UserDefaults.standard.object(forKey: "defaultMode") as? Int,
           let savedMode = TransportMode(rawValue: savedRaw) {
            defaultMode = savedMode
            currentMode = savedMode
        }

        // If we loaded a cached coordinate, mark it
        if location.coordinate != nil && location.horizontalAccuracy == -1 {
            loadedFromCache = true
        }

        locationCancellable = location.$coordinate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                self?.onLocationUpdate(coord)
            }

        // Activate WatchConnectivity for phone messages
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - WatchConnectivity

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { WatchPhoneSync.sendHello() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // The phone became reachable (e.g. it just opened) — re-announce so it greens promptly.
        if session.isReachable { WatchPhoneSync.sendHello() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePhoneMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePhoneMessage(message)
        }
        replyHandler(["status": "ok"])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let modeRaw = applicationContext["defaultMode"] as? Int,
               let mode = TransportMode(rawValue: modeRaw) {
                self?.defaultMode = mode
                UserDefaults.standard.set(modeRaw, forKey: "defaultMode")
            }
            self?.favouritesStore.handleReceivedContext(applicationContext)
            MyStationsStore.shared.handleReceivedContext(applicationContext)
        }
    }

    // Action-dispatched phone → watch contract, shared with the Garmin watch
    // (handlePhoneMessage in TrainTimeView.mc). The watch stays standalone; these only apply
    // an optional mirror when the phone drives it.
    private func handlePhoneMessage(_ data: [String: Any]) {
        guard let action = data["action"] as? String else { return }
        switch action {
        case "track":
            enterTrackingFromPhone(data)
        case "mode":
            if let raw = data["mode"] as? Int, let mode = TransportMode(rawValue: raw) {
                setModeFromPhone(mode)
            }
        case "station":
            showStationFromPhone(data)
        case "loc":
            if let lat = data["lat"] as? Double, let lon = data["lon"] as? Double {
                onPhoneLocation(lat: lat, lon: lon)
            }
        case "back":
            if appState == 2 { exitToStationView() }
        default:
            break
        }
    }

    private func enterTrackingFromPhone(_ data: [String: Any]) {
        guard let dest = data["dest"] as? String,
              let depTs = data["depTs"] as? Int else { return }

        let delay = data["delay"] as? Int ?? 0
        let plat = data["plat"] as? String ?? ""
        let platChg = data["platChg"] as? Bool ?? false

        if let stId = data["stId"] as? String {
            // Set station for API polling — find matching station or use ID directly
            // The next timer tick will fetch departures for this station
            _ = stId  // Station ID available for future API polling
        }

        // Wake from inactive
        if appState == 3 {
            lastInteractionTime = Date()
        }

        let category = data["cat"] as? String ?? ""
        let trainNumber = data["trainNum"] as? String
        let operatorRef = data["opRef"] as? String

        focusedTrain = FocusedDeparture(
            destination: dest,
            departureTimestamp: depTs,
            lineNumber: data["line"] as? String ?? "",
            category: category,
            trainNumber: trainNumber,
            operatorRef: operatorRef,
            delay: delay,
            platform: plat,
            platformChanged: platChg
        )
        appState = 2
        location.setTrackingAccuracy(true)
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = .distantPast
        formation = nil

        // Fetch formation for rail departures
        if let tn = trainNumber, Formation.isRailCategory(category),
           let stId = data["stId"] as? String {
            let date = formationDateString()
            Task { @MainActor in
                self.formation = try? await TrainAPIService.fetchFormation(trainNumber: tn, date: date, stationId: stId, operatorRef: operatorRef)
            }
        }

        startTimer(interval: Timing.trackingRefreshInterval)
        startExtendedSession()
        HapticService.shortPulse()
    }

    // Phone switched mode. Reuse the standalone selectMode when the mode is already loaded;
    // otherwise switch and fetch fresh stations from the effective position.
    private func setModeFromPhone(_ mode: TransportMode) {
        lastInteractionTime = Date()
        if appState == 3 { resumeFromInactive() }
        if availableModes.contains(mode) {
            selectMode(mode)
            return
        }
        currentMode = mode
        stationIndex = 0
        departures = []
        favouriteDepartures = []
        if let coord = effectivePosition(), !requestInFlight {
            fetchStations(lat: coord.latitude, lon: coord.longitude)
        }
    }

    // Phone selected a specific station. There's no standalone single-station path, so
    // synthesise the station, show it as the sole entry for its mode, and fetch its departures.
    private func showStationFromPhone(_ data: [String: Any]) {
        guard let stId = data["stId"] as? String else { return }
        lastInteractionTime = Date()
        if appState == 3 { resumeFromInactive() }
        let name = data["name"] as? String ?? "Station"
        let lat = data["lat"] as? Double
        let lon = data["lon"] as? Double
        let station = Station(id: stId, name: name, lat: lat, lon: lon, mode: currentMode, dist: nil, embeddedDepartures: nil)
        switch currentMode {
        case .train: trainStations = [station]
        case .bus: busStations = [station]
        case .tram: tramStations = [station]
        case .special: specialStations = [station]
        }
        if !availableModes.contains(currentMode) { availableModes = [currentMode] }
        stationIndex = 0
        appState = 0
        if let lat, let lon {
            lastSearchCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        departures = []
        favouriteDepartures = []
        fetchDepartures(stationId: stId)
    }

    // MARK: - Phone location backfill

    func onPhoneLocation(lat: Double, lon: Double) {
        phoneLat = lat
        phoneLon = lon
        phoneLocTs = Date()
        // Only act on it when our own GPS can't carry us — a good in-bounds fix stays primary.
        if !gpsUsableInBounds() {
            searchFromPhoneLocation()
        }
    }

    // Our own fix is present, accurate enough, and inside Switzerland.
    private func gpsUsableInBounds() -> Bool {
        guard let coord = location.coordinate else { return false }
        let usable = gpsQuality == .good || gpsQuality == .poor
        return usable && SwissBounds.contains(lat: coord.latitude, lon: coord.longitude)
    }

    private func phoneLocFresh() -> Bool {
        guard let ts = phoneLocTs else { return false }
        return Date().timeIntervalSince(ts) < 120
    }

    // The coordinate to act on: a usable in-bounds GPS fix wins; otherwise a fresh phone
    // location; otherwise any GPS fix; otherwise the last search anchor.
    private func effectivePosition() -> CLLocationCoordinate2D? {
        if gpsUsableInBounds() { return location.coordinate }
        if phoneLocFresh(), let lat = phoneLat, let lon = phoneLon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let coord = location.coordinate { return coord }
        return lastSearchCoordinate
    }

    private func searchFromPhoneLocation() {
        guard appState <= 1, phoneLocFresh(), let lat = phoneLat, let lon = phoneLon else { return }
        guard !requestInFlight else { return }
        if stations.isEmpty { status = "Updating stations..." }
        fetchStations(lat: lat, lon: lon)
    }

    // Ask the phone for its location when our GPS is weak. Throttled so we don't spam.
    private func requestPhoneLocation() {
        if let ts = lastLocRequestTs, Date().timeIntervalSince(ts) < 30 { return }
        lastLocRequestTs = Date()
        WatchPhoneSync.requestLocation()
    }

    // MARK: - Lifecycle

    func onAppear() {
        lastInteractionTime = Date()
        location.start()
        startTimer(interval: appState == 2 ? Timing.trackingRefreshInterval : Timing.normalRefreshInterval)
        // Announce we're up so a listening phone greens its link indicator at once.
        WatchPhoneSync.sendHello()
    }

    func onDisappear() {
        location.stop()
        stopTimer()
        endExtendedSession()
        // Tell the phone we're going away so it flips the indicator straight to amber.
        WatchPhoneSync.sendBye()
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
                if phoneLocFresh() {
                    searchFromPhoneLocation()
                } else {
                    requestPhoneLocation()
                    status = "GPS: Searching..."
                }
            }
            return
        }

        // Only gate initial search on Swiss bounds (border hysteresis)
        guard SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) || !stations.isEmpty else {
            if stations.isEmpty {
                // Our own fix is outside Switzerland — fall back to the phone's location.
                if phoneLocFresh() {
                    searchFromPhoneLocation()
                } else {
                    requestPhoneLocation()
                    status = "Not in Switzerland"
                }
            }
            return
        }

        // Skip station search in tracking/inactive (still update GPS above)
        if appState >= 2 { return }

        // If loaded from stale cache and now have a live GPS fix, refresh in place
        if loadedFromCache, location.gpsQuality == .good || location.gpsQuality == .poor {
            loadedFromCache = false
            if !requestInFlight {
                if stations.isEmpty { status = "Updating stations..." }
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

        // Liveness heartbeat: announce we're alive to a listening phone every ≥7 s. Sends
        // nothing when no phone is reachable. Matches the Garmin cadence.
        let nowSec = Int(Date().timeIntervalSince1970)
        if nowSec - lastAliveTsSec >= 7 {
            lastAliveTsSec = nowSec
            WatchPhoneSync.sendAlive()
        }

        // Request timeout check
        if requestInFlight, let startTime = requestStartTime,
           Date().timeIntervalSince(startTime) > Timing.requestTimeout {
            requestInFlight = false
            requestStartTime = nil
            if appState == 2 {
                consecutiveErrors += 1
            }
        }

        // Act on the effective position: our own fix when usable, else the phone's. When
        // neither exists, ask the phone for one and wait.
        guard let coord = effectivePosition() else {
            requestPhoneLocation()
            return
        }

        // Movement detection (only in station/selection view) — refresh in place
        if appState <= 1,
           let lastSearch = lastSearchCoordinate,
           location.hasMovedSignificantly(from: lastSearch) {
            fetchStations(lat: coord.latitude, lon: coord.longitude)
            return
        }

        // Update walk distance to current station
        if let station = currentStation, let stationCoord = station.coordinate {
            let haversine = GeoUtils.haversineDistance(from: coord, to: stationCoord)
            lastWalkDist = haversine
            lastWalkTime = nil

            if useRoutedDistance, let stationId = station.id {
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
                    exitToStationView()
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
            } else if SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) {
                fetchStations(lat: coord.latitude, lon: coord.longitude)
            } else {
                // Out of Switzerland with no stations — ask the phone for its location.
                requestPhoneLocation()
            }
        }
    }

    // MARK: - Departure Selection & Tracking

    func selectFavouriteDeparture(_ dep: Departure) {
        selectDepartureImpl(dep)
    }

    func selectDeparture(index: Int) {
        guard index >= 0, index < departures.count else { return }
        selectDepartureImpl(departures[index])
    }

    private func selectDepartureImpl(_ dep: Departure) {
        guard let depTs = dep.departureTimestamp, !dep.isGone else { return }

        focusedTrain = FocusedDeparture(
            destination: dep.destination,
            departureTimestamp: depTs,
            lineNumber: dep.lineNumber,
            category: dep.category,
            trainNumber: dep.trainNumber,
            operatorRef: dep.operatorRef,
            delay: dep.delay,
            platform: dep.platform,
            platformChanged: dep.platformChanged
        )
        appState = 2
        location.setTrackingAccuracy(true)
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = .distantPast  // Force immediate fetch on tracking entry
        formation = nil

        // Fetch formation for rail departures
        if let tn = dep.trainNumber, Formation.isRailCategory(dep.category),
           let stationId = currentStation?.id {
            let date = formationDateString()
            let opRef = dep.operatorRef
            Task { @MainActor in
                self.formation = try? await TrainAPIService.fetchFormation(trainNumber: tn, date: date, stationId: stationId, operatorRef: opRef)
            }
        }

        // Switch to faster timer for tracking
        startTimer(interval: Timing.trackingRefreshInterval)
        startExtendedSession()
        HapticService.shortPulse()

        // Reflect the same focused train on the phone (parity with the Garmin trackStarted echo).
        if let focused = focusedTrain {
            WatchPhoneSync.sendTrackStarted(focused, stationId: currentStation?.id)
        }
    }

    func enterInactiveState() {
        appState = 3
        location.setTrackingAccuracy(false)
        focusedTrain = nil
        formation = nil
        consecutiveErrors = 0
        startTimer(interval: Timing.normalRefreshInterval)
        endExtendedSession()
    }

    func resumeFromInactive() {
        lastInteractionTime = Date()
        appState = 0
    }

    func toggleRoutedDistance() {
        useRoutedDistance.toggle()
        UserDefaults.standard.set(useRoutedDistance, forKey: "useRoutedDistance")
    }

    func setDefaultMode(_ mode: TransportMode) {
        defaultMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "defaultMode")
        // Sync to phone via WCSession
        if WCSession.isSupported() && WCSession.default.activationState == .activated {
            try? WCSession.default.updateApplicationContext(["defaultMode": mode.rawValue])
        }
    }

    func toggleFavourite() {
        guard let focused = focusedTrain, let station = currentStation, let stationId = station.id else { return }
        favouritesStore.toggle(
            stationId: stationId,
            stationName: station.name ?? "Station",
            lineNumber: focused.lineNumber,
            destination: focused.destination
        )
    }

    var isFocusedTrainFavourite: Bool {
        guard let focused = focusedTrain, let stationId = currentStation?.id else { return false }
        return favouritesStore.isFavourite(stationId: stationId, lineNumber: focused.lineNumber, destination: focused.destination)
    }

    func isDepartureFavourite(_ departure: Departure) -> Bool {
        guard let stationId = currentStation?.id else { return false }
        return favouritesStore.isFavourite(stationId: stationId, lineNumber: departure.lineNumber, destination: departure.destination)
    }

    func exitToStationView() {
        lastInteractionTime = Date()
        appState = 0
        location.setTrackingAccuracy(false)
        focusedTrain = nil
        formation = nil
        consecutiveErrors = 0

        // Restore normal timer
        startTimer(interval: Timing.normalRefreshInterval)
        endExtendedSession()
    }

    private func formationDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Zurich")
        return fmt.string(from: Date())
    }

    // MARK: - API Calls

    private func fetchStations(lat: Double, lon: Double) {
        guard !requestInFlight else { return }
        requestInFlight = true
        requestStartTime = Date()

        Task {
            do {
                let result = try await TrainAPIService.fetchStations(lat: lat, lon: lon, mode: defaultMode)
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    let prevStationId = currentStation?.id
                    let pinnedIds = MyStationsStore.shared.ids()
                    trainStations = MyStationsStore.reorder(result.train, pinnedIds: pinnedIds)
                    busStations = MyStationsStore.reorder(result.bus, pinnedIds: pinnedIds)
                    tramStations = MyStationsStore.reorder(result.tram, pinnedIds: pinnedIds)
                    specialStations = MyStationsStore.reorder(result.special, pinnedIds: pinnedIds)
                    lastSearchCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    location.saveLastKnownCoordinate()
                    rebuildModesAndSelect(preserveStationId: prevStationId)

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

        let favParam = favouritesStore.favouritesParam(forStation: stationId)

        Task {
            do {
                let result = try await TrainAPIService.fetchDepartures(stationId: stationId, favourites: favParam)
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    lastFetchTime = Date()
                    consecutiveErrors = 0
                    departures = !result.favourites.isEmpty
                        ? favouritesStore.merging(favourites: result.favourites, into: result.departures)
                        : result.departures
                    favouriteDepartures = !result.favourites.isEmpty
                        ? result.favourites
                        : favouritesStore.extractFavourites(from: result.departures, stationId: stationId)

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
            // In tracking mode: keep existing data, continue countdown
            consecutiveErrors += 1
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
        favouriteDepartures = []
    }

}
