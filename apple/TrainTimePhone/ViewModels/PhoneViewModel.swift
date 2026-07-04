import SwiftUI
import CoreLocation
import Combine
import WidgetKit

class PhoneViewModel: ObservableObject {
    // Shown (and used as the gate for the faint Swiss-outline backdrop) when the phone is
    // located outside Switzerland with no stations to show.
    static let outOfBoundsStatus = "Not in Switzerland"

    // MARK: - Services
    let location = PhoneLocationService()
    private var locationCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var favouritesCancellable: AnyCancellable?

    // MARK: - App State
    @Published var appState: Int = 0 // 0=station view, 2=focused tracking, 3=inactive
    @Published var reviewRequestTick = 0 // bumped to ask the view to request an App Store review
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

    // MARK: - My stations (pinned)
    let myStationsStore = MyStationsStore.shared
    private var myStationsCancellable: AnyCancellable?

    // MARK: - Selection & Tracking
    @Published var showStationPicker = false
    @Published var focusedTrain: FocusedDeparture? = nil
    @Published var formation: Formation? = nil

    // MARK: - GPS
    @Published var gpsQuality: GPSQuality = .unavailable
    @Published var lastWalkDist: Double = 0
    @Published var lastWalkTime: Double? = nil
    @Published var useRoutedDistance: Bool = UserDefaults.standard.bool(forKey: "useRoutedDistance")

    // MARK: - Watch Connectivity
    let watchService = PhoneWatchService()
    @Published var connectedWatches: [PhoneConnectedWatch] = []
    @Published var watchSendStatus: String? = nil
    // Mirror phone state + location to the primary watch. Optional overlay; off → the
    // watch runs entirely on its own. Default on (absent key reads as true).
    @Published var mirrorToWatch: Bool = (UserDefaults.standard.object(forKey: "mirrorToWatch") as? Bool) ?? true
    // Which backend to drive when both an Apple Watch and a Garmin are paired.
    @Published var primaryWatch: PrimaryWatchPreference =
        PrimaryWatchPreference(rawValue: UserDefaults.standard.string(forKey: "primaryWatch") ?? "") ?? .auto

    // Mirroring internals
    private var mirrorWorkItem: DispatchWorkItem?
    private var lastPushedLoc: CLLocationCoordinate2D?
    private var lastLocPushTime: Date = .distantPast

    // Watch-app liveness. Each backend announces itself (hello/alive/bye); the phone never
    // pings (a message can wake a closed Garmin app, and Apple can't be launched at all).
    // Garmin arrives over the Connect IQ channel, Apple over the WCSession message channel.
    private var garminLastAlive: Date = .distantPast
    private var appleLastAlive: Date = .distantPast
    private var appleLastContact: Date = .distantPast // alive or bye — drives the amber window
    private var livenessTimer: AnyCancellable?
    // Bumped by the liveness ticker so the time-based indicator recomputes on each render.
    @Published private var livenessTick = 0
    // A Garmin open attempt is in flight (spinner). Apple can't be launched, so it's Garmin-only.
    @Published var watchChecking = false

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
    private var lastInteractionTime: Date = Date()

    // MARK: - Deep link pending
    private var pendingDeepLink: URL?

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
        if location.coordinate != nil && location.horizontalAccuracy == -1 {
            loadedFromCache = true
        }

        locationCancellable = location.$coordinate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                self?.onLocationUpdate(coord)
            }

        // Load default mode from UserDefaults
        if let savedRaw = UserDefaults.standard.object(forKey: "defaultMode") as? Int,
           let savedMode = TransportMode(rawValue: savedRaw) {
            defaultMode = savedMode
            currentMode = savedMode
        }

        // Persisted state sync (defaultMode / favourites / pinned) arrives over the Apple Watch
        // application context. Liveness + reqLoc arrive over the live message channels: Garmin
        // via Connect IQ, Apple via WCSession sendMessage. Each routes through applyReceivedWatch
        // tagged with its source so the right backend's liveness updates.
        watchService.wcService.onApplicationContextReceived = { [weak self] context in
            self?.applyReceivedWatchContext(context)
        }
        watchService.wcService.onMessageReceived = { [weak self] context in
            self?.applyReceivedWatch(context, source: .appleWatch)
        }
        watchService.garminService.onMessageReceived = { [weak self] context in
            self?.applyReceivedWatch(context, source: .garmin)
        }

        // Live status: a Garmin watch connecting/disconnecting re-checks eligibility so the
        // indicator and settings update without reopening the app.
        watchService.garminService.onLinkChanged = { [weak self] in
            DispatchQueue.main.async { self?.refreshConnectedWatches() }
        }

        // FavouritesStore is a separate ObservableObject the phone views reach through the
        // view model, so its changes don't republish on their own. Forward them: this both
        // drives star icons / row tints / Settings and re-extracts the top section
        // immediately rather than waiting for the next fetch (the 30s cooldown).
        favouritesCancellable = favouritesStore.$favourites
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.favouriteDepartures = self.extractFavouritesFromCurrent(self.departures)
            }

        // Pins changing (local toggle or a synced context) reorder the loaded
        // lists so pinned stations stay at the front without a refetch.
        myStationsCancellable = myStationsStore.$pinned
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPinnedReorder() }
    }

    // Live message from a watch (Garmin or Apple). Liveness announcements update that
    // backend's freshness; reqLoc is answered; anything else falls through to state sync.
    private func applyReceivedWatch(_ context: [String: Any], source: PhoneWatchType) {
        DispatchQueue.main.async {
            switch context["kind"] as? String {
            case "hello", "alive":
                self.markAlive(source)
            case "bye":
                self.markBye(source)
            case "reqLoc":
                self.replyWithLocation(to: source)
            default:
                self.applyReceivedWatchContext(context)
            }
        }
    }

    // A backend just announced it's open. Refresh its freshness and, on the transition into
    // alive, push the phone's current view so the watch jumps straight to it.
    private func markAlive(_ source: PhoneWatchType) {
        switch source {
        case .garmin:
            let wasAlive = garminAlive
            garminLastAlive = Date()
            watchChecking = false
            if !wasAlive { syncCurrentStateToWatch(to: .garmin) }
        case .appleWatch:
            let wasAlive = appleAlive
            appleLastAlive = Date()
            appleLastContact = Date()
            if !wasAlive { syncCurrentStateToWatch(to: .appleWatch) }
        }
    }

    private func markBye(_ source: PhoneWatchType) {
        switch source {
        case .garmin:
            garminLastAlive = .distantPast
        case .appleWatch:
            appleLastAlive = .distantPast
            appleLastContact = Date()
        }
    }

    // Applies a state sync pushed from any watch (defaultMode / favourites / pinned).
    // Unknown keys (e.g. a Garmin "trackStarted" echo) are ignored.
    private func applyReceivedWatchContext(_ context: [String: Any]) {
        DispatchQueue.main.async {
            if let modeRaw = context["defaultMode"] as? Int,
               let mode = TransportMode(rawValue: modeRaw) {
                self.defaultMode = mode
                UserDefaults.standard.set(modeRaw, forKey: "defaultMode")
            }
            self.favouritesStore.handleReceivedContext(context)
            self.myStationsStore.handleReceivedContext(context)
        }
    }

    // MARK: - Watch liveness + primary resolution

    private var garminAlive: Bool { Date().timeIntervalSince(garminLastAlive) <= 20 }
    private var appleAlive: Bool { Date().timeIntervalSince(appleLastAlive) <= 20 }

    /// The backend the phone drives. `auto` prefers Apple Watch when both are paired.
    var resolvedPrimaryWatch: PhoneWatchType? {
        let appleKnown = watchService.hasKnownAppleWatch
        let garminKnown = watchService.hasKnownGarmin
        switch primaryWatch {
        case .appleWatch: return appleKnown ? .appleWatch : (garminKnown ? .garmin : nil)
        case .garmin: return garminKnown ? .garmin : (appleKnown ? .appleWatch : nil)
        case .auto:
            if appleKnown { return .appleWatch }
            if garminKnown { return .garmin }
            return nil
        }
    }

    /// Both backends paired — show the Settings primary-watch picker.
    var bothWatchesKnown: Bool { watchService.hasKnownAppleWatch && watchService.hasKnownGarmin }

    var garminLiveness: WatchLiveness {
        _ = livenessTick
        let connected = watchService.hasGarminWatch
        if connected && garminAlive { return .green }
        if connected { return .amber }
        if watchService.hasKnownGarmin { return .grey }
        return .hidden
    }

    var appleWatchLiveness: WatchLiveness {
        _ = livenessTick
        guard watchService.hasKnownAppleWatch else { return .hidden }
        if watchService.wcService.isReachable && appleAlive { return .green }
        if Date().timeIntervalSince(appleLastContact) < 60 { return .amber }
        return .grey
    }

    /// Liveness of whichever backend is primary — what the header + tracking indicators show.
    var primaryWatchLiveness: WatchLiveness {
        switch resolvedPrimaryWatch {
        case .garmin: return garminLiveness
        case .appleWatch: return appleWatchLiveness
        case .none: return .hidden
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        lastInteractionTime = Date()
        location.start()
        startTimer(interval: appState == 2 ? Timing.trackingRefreshInterval : Timing.normalRefreshInterval)
        watchService.initialize()
        startLivenessTicker()
        // Feed an already-open watch the current location once device status has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshConnectedWatches()
            self?.pushLocationNow()
        }
    }

    func onDisappear() {
        updateWidgetCache() // the widget is only visible once we background; seed it with what was on screen
        location.stop()
        stopTimer()
        livenessTimer?.cancel()
        livenessTimer = nil
        watchService.shutdown()
    }

    // Passive ticker. Recomputes the time-based liveness indicator every 3 s without sending
    // anything (a phone message can wake a closed Garmin app; Apple can't be launched). The
    // watch announces itself with hello/alive/bye and the indicator follows.
    private func startLivenessTicker() {
        livenessTimer?.cancel()
        livenessTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.livenessTick &+= 1 }
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

    // MARK: - Location Update

    private func onLocationUpdate(_ coord: CLLocationCoordinate2D?) {
        gpsQuality = location.gpsQuality

        guard let coord = coord else {
            if stations.isEmpty {
                status = "GPS: Searching..."
            }
            return
        }

        // Keep a connected watch fed with the phone's location as a GPS fallback.
        maybePushLocationToWatch(coord)

        guard SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) || !stations.isEmpty else {
            if stations.isEmpty {
                status = Self.outOfBoundsStatus
            }
            return
        }

        // Skip station search in tracking/inactive (still update GPS above)
        if appState >= 2 { return }

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

        // Request timeout check
        if requestInFlight, let startTime = requestStartTime,
           Date().timeIntervalSince(startTime) > Timing.requestTimeout {
            requestInFlight = false
            requestStartTime = nil
            if appState == 2 {
                consecutiveErrors += 1
            }
        }

        guard let coord = location.coordinate else { return }

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
                // Departed >1 min ago: drop to the inactive tap-to-refresh state, not the
                // station view, so polling stops right away. The watch expires on its own depTs.
                if minutesLeft < -1.0 {
                    PhoneHapticService.shortPulse()
                    enterInactiveState()
                    return
                }

                let walkMin = lastWalkTime.map { $0 / 60.0 } ?? GeoUtils.walkMinutes(distanceMeters: lastWalkDist)
                let delay = Double(focused.delay)
                let effectBuf = minutesLeft - walkMin + delay
                if effectBuf < -0.5 {
                    let now = Int(Date().timeIntervalSince1970)
                    let interval = effectBuf < -2.0 ? 2 : 4
                    if now - lastVibeTick >= interval {
                        PhoneHapticService.heartbeat()
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

        if appState == 3 { return }

        // Fetch departures if cooldown elapsed
        if !requestInFlight,
           Date().timeIntervalSince(lastFetchTime) >= (appState == 2 ? Timing.fetchCooldownTracking : Timing.fetchCooldownNormal) {
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            } else if stations.isEmpty,
                      SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) {
                fetchStations(lat: coord.latitude, lon: coord.longitude)
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
        lastFetchTime = .distantPast
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

        startTimer(interval: Timing.trackingRefreshInterval)
        PhoneHapticService.shortPulse()
        maybeRequestReview()

        // Mirror the same focused train onto the watch (immediate — a tap is a
        // strong, deliberate action).
        if let focused = focusedTrain {
            mirror(PhoneWatchService.GarminPayload.track(focused, stationId: currentStation?.id))
        }
    }

    func enterInactiveState() {
        appState = 3
        location.setTrackingAccuracy(false)
        focusedTrain = nil
        formation = nil
        consecutiveErrors = 0
        startTimer(interval: Timing.normalRefreshInterval)
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
        watchService.wcService.updateApplicationContext(["defaultMode": mode.rawValue])
    }

    /// Count tracking sessions and ask for a review once the user has tracked a few
    /// departures, at most once per app version. The system sheet is itself rate limited.
    private func maybeRequestReview() {
        let count = UserDefaults.standard.integer(forKey: "reviewTrackCount") + 1
        UserDefaults.standard.set(count, forKey: "reviewTrackCount")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard count >= 3, UserDefaults.standard.string(forKey: "reviewPromptedVersion") != version else { return }
        UserDefaults.standard.set(version, forKey: "reviewPromptedVersion")
        reviewRequestTick += 1
    }

    func toggleFavourite() {
        guard let focused = focusedTrain else { return }
        toggleFavourite(lineNumber: focused.lineNumber, destination: focused.destination)
    }

    func toggleFavourite(departure: Departure) {
        toggleFavourite(lineNumber: departure.lineNumber, destination: departure.destination)
    }

    private func toggleFavourite(lineNumber: String, destination: String) {
        guard let station = currentStation, let stationId = station.id else { return }
        lastInteractionTime = Date() // curating favourites shouldn't trip the inactivity timeout
        favouritesStore.toggle(
            stationId: stationId,
            stationName: station.name ?? "Station",
            lineNumber: lineNumber,
            destination: destination
        )
        PhoneHapticService.shortPulse()
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
        let wasTracking = appState == 2
        lastInteractionTime = Date()
        appState = 0
        location.setTrackingAccuracy(false)
        focusedTrain = nil
        formation = nil
        consecutiveErrors = 0
        startTimer(interval: Timing.normalRefreshInterval)
        // Mirror the exit so the watch leaves tracking and returns to its station view.
        if wasTracking { mirror(["action": "back"]) }
    }

    // MARK: - Mode Navigation

    func cycleMode() {
        lastInteractionTime = Date()
        guard availableModes.count > 1 else { return }
        if let idx = availableModes.firstIndex(of: currentMode) {
            let nextIdx = (idx + 1) % availableModes.count
            selectMode(availableModes[nextIdx])
        }
    }

    func selectMode(_ mode: TransportMode) {
        lastInteractionTime = Date()
        guard mode != currentMode else { return }
        currentMode = mode
        stationIndex = 0

        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            favouriteDepartures = extractFavouritesFromCurrent(deps)
            lastFetchTime = Date()
        } else {
            departures = []
            favouriteDepartures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }

        mirrorDebounced { PhoneWatchService.GarminPayload.mode(mode.rawValue) }
    }

    func selectStation(index: Int) {
        lastInteractionTime = Date()
        guard index >= 0, index < stations.count else { return }
        stationIndex = index
        showStationPicker = false

        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            favouriteDepartures = extractFavouritesFromCurrent(deps)
            lastFetchTime = Date()
        } else {
            departures = []
            favouriteDepartures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }

        if let st = currentStation, let id = st.id {
            let name = st.name ?? "Station"
            let coord = st.coordinate
            mirrorDebounced {
                PhoneWatchService.GarminPayload.station(id: id, name: name, lat: coord?.latitude, lon: coord?.longitude)
            }
        }
    }

    // MARK: - Pinned "My stations"

    func isStationPinned(_ id: String?) -> Bool {
        guard let id else { return false }
        return myStationsStore.isPinned(id)
    }

    func togglePinnedStation(_ station: Station) {
        lastInteractionTime = Date()
        myStationsStore.toggle(station)
        // The $pinned subscription also reorders, but call directly so the
        // change is immediate even if publishing is coalesced.
        applyPinnedReorder()
    }

    /// Re-sort the already-loaded lists so pinned stations sit at the front,
    /// keeping the currently-shown station selected (pinning is a default, it
    /// doesn't yank the user off the station they're looking at).
    private func applyPinnedReorder() {
        let pinnedIds = myStationsStore.ids()
        let selectedId = currentStation?.id
        trainStations = MyStationsStore.reorder(trainStations, pinnedIds: pinnedIds)
        busStations = MyStationsStore.reorder(busStations, pinnedIds: pinnedIds)
        tramStations = MyStationsStore.reorder(tramStations, pinnedIds: pinnedIds)
        specialStations = MyStationsStore.reorder(specialStations, pinnedIds: pinnedIds)
        if let selectedId, let (mode, idx) = locate(stationId: selectedId) {
            currentMode = mode
            stationIndex = idx
        }
    }

    /// Find a station by id across all mode arrays, returning its (mode, index).
    private func locate(stationId: String) -> (TransportMode, Int)? {
        let groups: [(TransportMode, [Station])] = [
            (.train, trainStations), (.bus, busStations),
            (.tram, tramStations), (.special, specialStations)
        ]
        for (mode, list) in groups {
            if let idx = list.firstIndex(where: { $0.id == stationId }) {
                return (mode, idx)
            }
        }
        return nil
    }

    /// Rebuild the mode list after a station fetch. When `preserveStationId` still
    /// exists in the new results, keep the user on that station/mode (in-place refresh,
    /// no reset to the nearest station); otherwise fall back to selecting the nearest.
    private func rebuildModesAndSelect(preserveStationId: String? = nil) {
        var modes: [TransportMode] = []
        if !trainStations.isEmpty { modes.append(.train) }
        if !busStations.isEmpty { modes.append(.bus) }
        if !tramStations.isEmpty { modes.append(.tram) }
        if !specialStations.isEmpty { modes.append(.special) }
        availableModes = modes

        var preserved = false
        if let id = preserveStationId, let (mode, idx) = locate(stationId: id) {
            currentMode = mode
            stationIndex = idx
            preserved = true
        } else {
            if stations.isEmpty {
                if modes.contains(defaultMode) {
                    currentMode = defaultMode
                } else if let firstMode = modes.first {
                    currentMode = firstMode
                }
            }
            stationIndex = 0
        }

        // Adopt fresh embedded departures if present. On the non-preserved path, blank
        // and refetch. On the preserved path with no fresh embedded departures, leave the
        // existing list untouched (no flash) — the timer refresh updates it in place.
        if let deps = currentStation?.embeddedDepartures, !deps.isEmpty {
            departures = deps
            favouriteDepartures = extractFavouritesFromCurrent(deps)
            lastFetchTime = Date()
        } else if !preserved {
            departures = []
            favouriteDepartures = []
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            }
        }

        // Handle pending deep link after stations load
        if let url = pendingDeepLink {
            pendingDeepLink = nil
            handleDeepLink(url)
        }
    }

    private func clearStationState() {
        trainStations = []
        busStations = []
        tramStations = []
        specialStations = []
        stationIndex = 0
        departures = []
        favouriteDepartures = []
        availableModes = []
        consecutiveErrors = 0

        if appState == 2 {
            exitToStationView()
        }

        routing.clearCache()
        status = "Finding stations..."
    }

    // MARK: - Focused Train Update

    private func updateFocusedTrain() {
        guard var focused = focusedTrain else { return }

        let matches = departures.filter {
            $0.destination == focused.destination && $0.minutesUntil >= -1
        }
        guard let best = matches.min(by: {
            abs(Double($0.minutesUntil) - focused.minutesUntil) <
            abs(Double($1.minutesUntil) - focused.minutesUntil)
        }) else {
            PhoneHapticService.shortPulse()
            exitToStationView()
            return
        }

        let oldPlatform = focused.platform
        if best.platform != oldPlatform && !best.platform.isEmpty {
            if best.platformChanged {
                PhoneHapticService.doublePulse()
            }
            focused.platform = best.platform
            focused.platformChanged = best.platformChanged
        }

        focused.delay = best.delay
        focusedTrain = focused
    }

    // MARK: - Tracking Calculations

    var trackingScheduledBuffer: Double {
        guard let focused = focusedTrain else { return 0 }
        let walkMin = lastWalkTime.map { $0 / 60.0 } ?? GeoUtils.walkMinutes(distanceMeters: lastWalkDist)
        return focused.minutesUntil - walkMin
    }

    var trackingEffectiveBuffer: Double {
        guard let focused = focusedTrain else { return 0 }
        return trackingScheduledBuffer + Double(focused.delay)
    }

    var trackingStatusText: String {
        let buf = trackingEffectiveBuffer
        if gpsQuality == .unavailable { return "No GPS" }
        let absBuf = abs(buf)
        if absBuf < 0.5 { return "On time" }
        let unit = absBuf < 1.5 ? "\(Int(absBuf * 60))s" : "\(Int(absBuf)) min"
        return buf > 0 ? "\(unit) ahead" : "\(unit) behind"
    }

    var trackingStatusColor: Color {
        let buf = trackingEffectiveBuffer
        if gpsQuality == .unavailable { return AppColors.barGray }
        if buf > 0.5 { return AppColors.ahead }
        if buf < -0.5 { return AppColors.behind }
        return AppColors.onTime
    }

    var directionToStation: Double? {
        guard let userCoord = location.coordinate,
              let station = currentStation,
              let stationCoord = station.coordinate,
              let heading = location.heading else { return nil }
        let bearing = GeoUtils.bearing(from: userCoord, to: stationCoord)
        return (bearing - heading) * 180.0 / .pi
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
                    let pinnedIds = myStationsStore.ids()
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
        Task { await fetchDeparturesAsync(stationId: stationId) }
    }

    @MainActor
    private func fetchDeparturesAsync(stationId: String) async {
        guard !requestInFlight else { return }
        requestInFlight = true
        requestStartTime = Date()

        let favParam = favouritesStore.favouritesParam(forStation: stationId)

        do {
            let result = try await TrainAPIService.fetchDepartures(stationId: stationId, favourites: favParam)
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

            if appState == 2 {
                updateFocusedTrain()
            }
        } catch {
            requestInFlight = false
            requestStartTime = nil
            handleError(error, context: "Departures")
        }
    }

    /// Pull-to-refresh: bypasses the timer cooldown by calling the fetch directly.
    @MainActor
    func forceRefresh() async {
        lastInteractionTime = Date()
        var waited = 0
        while requestInFlight && waited < 100 { // ride out an in-flight timer fetch (≤10s)
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard let id = currentStation?.id else { return }
        await fetchDeparturesAsync(stationId: id)
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error, context: String) {
        if appState == 2 {
            // In tracking mode: keep existing data, continue countdown
            consecutiveErrors += 1
            return
        }

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

    // MARK: - Watch Sending

    func refreshConnectedWatches() {
        watchService.refreshConnectedWatches()
        connectedWatches = watchService.connectedWatches
    }

    func sendToWatch(_ watch: PhoneConnectedWatch) {
        guard let focused = focusedTrain else { return }
        let stationId = currentStation?.id
        watchService.sendTrackCommand(to: watch, departure: focused, stationId: stationId) { [weak self] success in
            DispatchQueue.main.async {
                self?.watchSendStatus = success ? "Sent to \(watch.name)" : "Failed to send"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.watchSendStatus = nil
                }
            }
        }
    }

    func sendToWatch() {
        guard let watch = connectedWatches.first else {
            watchSendStatus = "No watch connected"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.watchSendStatus = nil
            }
            return
        }
        sendToWatch(watch)
    }

    // MARK: - Watch mirroring (backend-dispatched to the primary watch)

    func setMirrorToWatch(_ value: Bool) {
        mirrorToWatch = value
        UserDefaults.standard.set(value, forKey: "mirrorToWatch")
    }

    func setPrimaryWatch(_ value: PrimaryWatchPreference) {
        primaryWatch = value
        UserDefaults.standard.set(value.rawValue, forKey: "primaryWatch")
    }

    // Low-level send to a specific backend. Garmin: can't wake a closed app, so gate on
    // liveness. Apple: WCSession.mirror sends live only when reachable, else drops (the
    // watch re-syncs on its next launch via hello). Both no-op when mirroring is off.
    private func send(_ data: [String: Any], to backend: PhoneWatchType) {
        guard mirrorToWatch else { return }
        switch backend {
        case .garmin:
            guard garminAlive else { return }
            watchService.sendToGarminWatches(data)
        case .appleWatch:
            watchService.sendToAppleWatch(data)
        }
    }

    // Immediate push (track / back — a deliberate action) to the primary watch.
    private func mirror(_ data: [String: Any]) {
        guard let backend = resolvedPrimaryWatch else { return }
        send(data, to: backend)
    }

    // Debounced push (mode cycling / station scrolling) — the latest settled state wins,
    // so the channel isn't flooded.
    private func mirrorDebounced(_ build: @escaping () -> [String: Any]) {
        guard let backend = resolvedPrimaryWatch else { return }
        mirrorWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.send(build(), to: backend)
        }
        mirrorWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // Proactive location backfill: feed the phone's coordinate to the watch as a GPS
    // fallback. Debounced ≥10 s / ≥100 m so a settled phone (or a mock-GPS app) keeps the
    // watch fed without flooding.
    private func maybePushLocationToWatch(_ coord: CLLocationCoordinate2D) {
        guard resolvedPrimaryWatch != nil else { return }
        let movedEnough = lastPushedLoc.map { GeoUtils.haversineDistance(from: $0, to: coord) >= 100 } ?? true
        if !movedEnough, Date().timeIntervalSince(lastLocPushTime) < 10 { return }
        lastPushedLoc = coord
        lastLocPushTime = Date()
        mirror(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude))
    }

    // Force-push the current location to the primary watch, bypassing the debounce. Used on
    // app open so a watch sitting on "Not in Switzerland" picks up the phone's position.
    private func pushLocationNow() {
        guard let coord = location.coordinate else { return }
        lastPushedLoc = coord
        lastLocPushTime = Date()
        mirror(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude))
    }

    // Reply to a backend's explicit reqLoc with the phone's current coordinate.
    private func replyWithLocation(to source: PhoneWatchType) {
        guard mirrorToWatch, let coord = location.coordinate else { return }
        send(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude), to: source)
    }

    // Push the phone's current view onto a freshly-opened watch: location, plus either the
    // tracked train or the current station. The peer of Android's syncCurrentStateToWatch.
    private func syncCurrentStateToWatch(to backend: PhoneWatchType) {
        guard mirrorToWatch, let coord = location.coordinate else {
            // No location yet — still mirror the view if we have one.
            sendCurrentView(to: backend)
            return
        }
        send(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude), to: backend)
        lastPushedLoc = coord
        lastLocPushTime = Date()
        sendCurrentView(to: backend)
    }

    private func sendCurrentView(to backend: PhoneWatchType) {
        if appState == 2, let focused = focusedTrain {
            send(PhoneWatchService.GarminPayload.track(focused, stationId: currentStation?.id), to: backend)
        } else if let st = currentStation, let id = st.id {
            let coord = st.coordinate
            send(PhoneWatchService.GarminPayload.station(id: id, name: st.name ?? "Station", lat: coord?.latitude, lon: coord?.longitude), to: backend)
        }
    }

    // Tap on the watch indicator / "Open on watch" button. Garmin can be launched remotely;
    // Apple Watch cannot (no API), so it re-syncs when reachable or guides the user otherwise.
    func openWatchApp() {
        switch resolvedPrimaryWatch {
        case .garmin:
            refreshConnectedWatches()
            if !watchService.hasGarminWatch {
                showWatchStatus("No watch connected")
                return
            }
            if garminAlive {
                syncCurrentStateToWatch(to: .garmin)
                return
            }
            watchChecking = true
            watchService.openGarminApp()
            // The watch sends hello once it starts, flipping us to alive + a state sync.
            // Settle the spinner if nothing arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.watchChecking = false
            }
        case .appleWatch:
            if watchService.wcService.isReachable {
                syncCurrentStateToWatch(to: .appleWatch)
            } else {
                showWatchStatus("Open TrainTime on your watch")
            }
        case .none:
            showWatchStatus("No watch connected")
        }
    }

    private func showWatchStatus(_ message: String) {
        watchSendStatus = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.watchSendStatus = nil
        }
    }

    // MARK: - Formation

    private func formationDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Zurich")
        return fmt.string(from: Date())
    }

    private func extractFavouritesFromCurrent(_ deps: [Departure]) -> [Departure] {
        guard let stationId = currentStation?.id else { return [] }
        return favouritesStore.extractFavourites(from: deps, stationId: stationId)
    }

    // MARK: - Widget Cache

    /// Seed the widget's App Group cache with what the user last saw, so the widget shows live
    /// data without its own Refresh tap. Called on background (the widget is only visible then).
    /// Piggybacks on fetches the user already triggered, so it adds no polling, and the fresh
    /// fetchTime re-arms the widget's active window before it goes dormant — the breaker holds.
    private func updateWidgetCache() {
        guard currentStation != nil else { return }
        let result = WidgetFetchResult(
            train: widgetStations(trainStations, mode: .train),
            bus: widgetStations(busStations, mode: .bus),
            tram: widgetStations(tramStations, mode: .tram),
            special: widgetStations(specialStations, mode: .special),
            selectedModeRaw: currentMode.rawValue,
            selectedStationIndex: stationIndex,
            fetchTime: Date().timeIntervalSince1970
        )
        result.cache()
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainTimeWidget")
    }

    /// The selected station carries the full, freshly-fetched departure list; the rest carry
    /// whatever the nearby search embedded.
    private func widgetStations(_ list: [Station], mode: TransportMode) -> [WidgetStation] {
        list.compactMap { station in
            guard let id = station.id, let name = station.name else { return nil }
            let deps: [Departure]
            if mode == currentMode, id == currentStation?.id, !departures.isEmpty {
                deps = departures
            } else {
                deps = station.embeddedDepartures ?? []
            }
            return WidgetStation(id: id, name: name, departures: deps.map(widgetDeparture))
        }
    }

    private func widgetDeparture(_ dep: Departure) -> WidgetDeparture {
        WidgetDeparture(
            destination: dep.destination,
            departureTimestamp: dep.departureTimestamp ?? 0,
            delay: dep.delay,
            platform: dep.platform,
            platformChanged: dep.platformChanged,
            lineNumber: dep.lineNumber
        )
    }

    // MARK: - Deep Link

    func handleDeepLink(_ url: URL) {
        lastInteractionTime = Date()
        guard url.scheme == "traintime" else { return }

        // traintime://sbbshare — just open the app (SBB share trigger)
        if url.host == "sbbshare" {
            if appState == 3 { resumeFromInactive() }
            return
        }

        // traintime://track?destination=DEST&timestamp=TS
        guard url.host == "track" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let destination = components.queryItems?.first(where: { $0.name == "destination" })?.value,
              let tsString = components.queryItems?.first(where: { $0.name == "timestamp" })?.value,
              let timestamp = Int(tsString) else { return }

        // If we don't have departures yet, save for later
        if departures.isEmpty {
            pendingDeepLink = url
            return
        }

        // Find matching departure and select it
        if let index = departures.firstIndex(where: {
            $0.destination == destination && $0.departureTimestamp == timestamp
        }) {
            selectDeparture(index: index)
        }
    }
}
