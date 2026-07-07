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
    @Published var showReviewPrompt = false // timed review ask (Yes / Not now / Don't ask again)
    @Published var openWriteReviewTick = 0 // a watch asked to rate; the view opens the write-review page
    @Published var status: String = "GPS: Searching..."

    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6760388620?action=write-review")!
    let reviewStore = ReviewStore()

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
    /// True while a departures fetch is in flight. The station list dims the
    /// existing rows and shows a slim bar instead of blanking to a full-screen
    /// spinner, so a refresh freezes the board rather than hiding it.
    @Published var departuresRefreshing = false

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
    private var appleLastContact: Date = .distantPast // alive or bye, drives the amber window
    // Version last announced by each backend (nil until first heard). Drives the
    // Send-to-Watch update guard; a pre-versioning watch reports 0.4.x / protocol 0.
    private var garminWatchProtocol: Int?
    private var garminWatchVersion: String?
    private var appleWatchProtocol: Int?
    private var appleWatchVersion: String?
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
    // The visible station was launched directly (shared route / resume), not
    // from a nearby search. On exit we re-search at real GPS so we don't strand
    // the user on the remote origin.
    private var launchedStationActive = false
    var consecutiveErrors: Int = 0
    private var lastVibeTick: Int = 0
    private var tickCount: Int = 0
    private var loadedFromCache = false
    private var lastInteractionTime: Date = Date()

    // MARK: - Deep link pending
    private var pendingDeepLink: URL?

    // MARK: - Shared SBB route intake
    // pendingShareTrack is one-shot: the departures fetch it triggered
    // consumes it, so an unrelated board can't auto-track.
    let pendingRouteStore = PendingRouteStore.shared
    @Published var shareStatus: String? = nil
    @Published var shareReplaceOffer: SharedRouteOffer? = nil
    @Published var resumeOffer: Departure? = nil
    private var pendingShareTrack: SharedRouteOffer?
    private var resumeCheckInFlight = false

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
        reviewStore.ensureFirstLaunchTimestamp()

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
                self.markAlive(source, context: context)
            case "bye":
                self.markBye(source)
            case "reqLoc":
                self.replyWithLocation(to: source)
            case "rateApp":
                // The watch has no review page of its own; open ours.
                self.openWriteReviewTick += 1
            default:
                self.applyReceivedWatchContext(context)
            }
        }
    }

    // A backend just announced it's open. Refresh its freshness and, on the transition into
    // alive, push the phone's current view so the watch jumps straight to it.
    private func markAlive(_ source: PhoneWatchType, context: [String: Any]) {
        // A pre-versioning watch sends no v/pv: read as 0.4.x / protocol 0.
        let pv = context["pv"] as? Int ?? 0
        let v = context["v"] as? String ?? WatchSyncProtocol.legacyVersionName
        switch source {
        case .garmin:
            garminWatchProtocol = pv
            garminWatchVersion = v
            let wasAlive = garminAlive
            garminLastAlive = Date()
            watchChecking = false
            if !wasAlive { syncCurrentStateToWatch(to: .garmin) }
        case .appleWatch:
            appleWatchProtocol = pv
            appleWatchVersion = v
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

    /// Both backends paired. Show the Settings primary-watch picker.
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

    /// Liveness of whichever backend is primary, what the header + tracking indicators show.
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

        // Movement detection (only in station/selection view), refresh in place
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
        beginTracking(FocusedDeparture(
            destination: dep.destination,
            departureTimestamp: depTs,
            lineNumber: dep.lineNumber,
            category: dep.category,
            trainNumber: dep.trainNumber,
            operatorRef: dep.operatorRef,
            delay: dep.delay,
            platform: dep.platform,
            platformChanged: dep.platformChanged
        ))
        // Only a real board tap counts toward the review ask.
        maybeRequestReview()
    }

    /// Track a shared-route leg whose train isn't on the live board yet. The
    /// countdown is fully local (derived from depTs), so it runs without a board
    /// match. updateFocusedTrain keeps it until the train actually departs, then
    /// a live board match upgrades it with delay/platform.
    private func enterProtectedTrack(_ leg: RouteLeg) {
        beginTracking(FocusedDeparture(
            destination: leg.destName,
            departureTimestamp: leg.depTs,
            lineNumber: leg.lineNumber ?? "",
            category: leg.category ?? "",
            trainNumber: leg.trainNumber,
            operatorRef: nil,
            delay: 0,
            platform: "",
            platformChanged: false
        ))
    }

    /// Shared tracking entry: from a real board tap or a synthesised shared-route
    /// leg. Everything downstream (timer cadence, watch/Garmin mirror, formation)
    /// is identical once we have a FocusedDeparture.
    private func beginTracking(_ focused: FocusedDeparture) {
        focusedTrain = focused
        appState = 2
        location.setTrackingAccuracy(true)
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = .distantPast
        formation = nil

        // Fetch formation for rail departures
        if let tn = focused.trainNumber, Formation.isRailCategory(focused.category),
           let stationId = currentStation?.id {
            let date = formationDateString()
            let opRef = focused.operatorRef
            Task { @MainActor in
                self.formation = try? await TrainAPIService.fetchFormation(trainNumber: tn, date: date, stationId: stationId, operatorRef: opRef)
            }
        }

        startTimer(interval: Timing.trackingRefreshInterval)
        PhoneHapticService.shortPulse()

        // Mirror the same focused train onto the watch (immediate: a tap is a
        // strong, deliberate action).
        mirror(PhoneWatchService.GarminPayload.track(focused, station: currentStation))
    }

    func enterInactiveState() {
        onTrackingEnded(appState == 2 ? focusedTrain?.departureTimestamp : nil)
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

    /// Paused-screen resume (terminal user action, no launch follows), so it can
    /// safely re-search: a shared route that timed out into inactive returns to
    /// the user's real location instead of the remote origin board.
    func resumeToStationView() {
        resumeFromInactive()
        returnToNearbyIfLaunched()
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

    /// Count tracking sessions and surface the timed review ask when the shared
    /// gate passes. Shown counts as asked for this version, whatever button follows.
    private func maybeRequestReview() {
        reviewStore.incrementTrackCount()
        guard reviewStore.shouldPrompt() else { return }
        reviewStore.markPrompted(version: ReviewStore.currentVersion)
        showReviewPrompt = true
    }

    func snoozeReview() {
        reviewStore.snooze()
    }

    func optOutReview() {
        reviewStore.optOut()
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
        onTrackingEnded(wasTracking ? focusedTrain?.departureTimestamp : nil)
        lastInteractionTime = Date()
        appState = 0
        location.setTrackingAccuracy(false)
        focusedTrain = nil
        formation = nil
        consecutiveErrors = 0
        startTimer(interval: Timing.normalRefreshInterval)
        // A shared route launched a remote origin station. Go back to the
        // nearby list at the user's real location rather than that origin.
        returnToNearbyIfLaunched()
        // Deliberately do NOT tell the watch to leave tracking. The watch tracks
        // independently, and tracking is the end game there, it must not be
        // interrupted by the phone going back. Selecting another departure sends
        // a fresh track command, which is the only thing that switches it.
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
            // Keep the previous list (greyed via departuresRefreshing) until the
            // new board arrives, rather than blanking to a spinner.
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
            // Keep the previous list (greyed via departuresRefreshing) until the
            // new board arrives, rather than blanking to a spinner.
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
        // existing list untouched (no flash), the timer refresh updates it in place.
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

        // Match by train number when we have one (a protected shared-route leg
        // carries it), so live platform/delay are adopted even though the leg's
        // destName is the alight stop, not the board's terminus. Fall back to
        // destination for board taps that lack a train number (buses/trams).
        let matches = departures.filter {
            ($0.destination == focused.destination ||
                (focused.trainNumber != nil && $0.trainNumber == focused.trainNumber)) &&
                $0.minutesUntil >= -1
        }
        guard let best = matches.min(by: {
            abs(Double($0.minutesUntil) - focused.minutesUntil) <
            abs(Double($1.minutesUntil) - focused.minutesUntil)
        }) else {
            // A still-future train just isn't on the board yet (a shared route
            // opened early, before it reaches the 20-row horizon). Keep the
            // local countdown; only give up once it has actually departed.
            let nowS = Int(Date().timeIntervalSince1970)
            if nowS < focused.departureTimestamp + PendingRouteLogic.graceSec { return }
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
        // A real nearby search supersedes any launched remote station.
        launchedStationActive = false
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
        departuresRefreshing = true

        let favParam = favouritesStore.favouritesParam(forStation: stationId)

        do {
            let result = try await TrainAPIService.fetchDepartures(stationId: stationId, favourites: favParam)
            requestInFlight = false
            requestStartTime = nil
            departuresRefreshing = false
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
            await tryEnterPendingShareTrack()
        } catch {
            requestInFlight = false
            requestStartTime = nil
            departuresRefreshing = false
            // Offline or server error: the shared route must not be lost:
            // queue it; the resume flow re-checks the board later.
            if let offer = pendingShareTrack {
                pendingShareTrack = nil
                saveOfferAsQueued(offer)
            }
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

    // Returns the watch's version when it has announced a protocol below the
    // minimum (too old to receive the track command), else nil. A watch not yet
    // heard from (nil protocol) gets the benefit of the doubt and the send runs.
    private func outdatedWatchVersion(for type: PhoneWatchType) -> String? {
        let pv: Int?
        let v: String?
        switch type {
        case .garmin: pv = garminWatchProtocol; v = garminWatchVersion
        case .appleWatch: pv = appleWatchProtocol; v = appleWatchVersion
        }
        guard let pv, pv < WatchSyncProtocol.minTrackProtocol else { return nil }
        return v ?? WatchSyncProtocol.legacyVersionName
    }

    func sendToWatch(_ watch: PhoneConnectedWatch) {
        guard let focused = focusedTrain else { return }
        if let version = outdatedWatchVersion(for: watch.type) {
            watchSendStatus = "Update TrainTime on your watch (\(version))"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.watchSendStatus = nil
            }
            return
        }
        watchService.sendTrackCommand(to: watch, departure: focused, station: currentStation) { [weak self] success in
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

    // Tracking-screen watch button: a live primary watch takes an explicit
    // send, a closed one the launch/re-sync path (a closed Garmin app needs
    // the open request before it can receive).
    func sendToPrimaryOrOpen() {
        refreshConnectedWatches()
        if primaryWatchLiveness == .green {
            sendToWatch()
        } else {
            openWatchApp()
        }
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

    // Immediate push (track / back: a deliberate action) to the primary watch.
    private func mirror(_ data: [String: Any]) {
        guard let backend = resolvedPrimaryWatch else { return }
        send(data, to: backend)
    }

    // Debounced push (mode cycling / station scrolling), the latest settled state wins,
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
            // No location yet, still mirror the view if we have one.
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
            send(PhoneWatchService.GarminPayload.track(focused, station: currentStation), to: backend)
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
    /// fetchTime re-arms the widget's active window before it goes dormant. The breaker holds.
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

        // traintime://sbbshare[?url=...], wake the app and consume the
        // payload the share extension left in the App Group. The url param is
        // the simctl-testable path, mirroring Android.
        if url.host == "sbbshare" {
            if appState == 3 { resumeFromInactive() }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let shared = components.queryItems?.first(where: { $0.name == "url" })?.value {
                handleSharedText(shared)
            } else {
                consumeSharePayload()
            }
            return
        }

        // traintime://resumeroute, reminder notification tap.
        if url.host == "resumeroute" {
            if appState == 3 { resumeFromInactive() }
            Task { @MainActor in await refreshPendingRoute() }
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

    // MARK: - Shared SBB trip intake (share extension / sbbshare deep link)

    private static let sharePayloadKey = "sbbSharePayload"
    private static let sharePayloadTsKey = "sbbSharePayloadTs"

    /// Read + clear the extension's handoff. Also called on scenePhase
    /// active: openURL from extensions is flaky, so a fresh payload gets
    /// consumed even when the deep link never fired.
    func consumeSharePayload() {
        let store = SharedDefaults.store
        guard let payload = store.string(forKey: Self.sharePayloadKey) else { return }
        let ts = store.double(forKey: Self.sharePayloadTsKey)
        store.removeObject(forKey: Self.sharePayloadKey)
        store.removeObject(forKey: Self.sharePayloadTsKey)
        // Stale handoff (e.g. the extension ran hours ago and the open failed).
        guard Date().timeIntervalSince1970 - ts < 300 else { return }
        handleSharedText(payload)
    }

    func handleSharedText(_ text: String) {
        lastInteractionTime = Date()
        if appState == 3 { resumeFromInactive() }
        guard let link = SBBShareLink.find(in: text) else {
            shareStatus = "No SBB trip link found"
            return
        }
        var sourceUrl: String?
        if case .short(let url) = link { sourceUrl = url }
        Task { @MainActor in
            do {
                let route = try await SBBShareService.resolve(link)
                await openSharedRoute(SharedRouteOffer(route: route, sourceUrl: sourceUrl))
            } catch let error as SBBDecodeError {
                switch error {
                case .unsupportedVersion: shareStatus = "This SBB link format isn't supported yet"
                case .noRideLegs: shareStatus = "Nothing to track in this trip"
                case .malformed: shareStatus = "Couldn't read this trip link"
                }
            } catch {
                shareStatus = "Couldn't open the link. Check your connection"
            }
        }
    }

    @MainActor
    private func openSharedRoute(_ offer: SharedRouteOffer) async {
        if let existing = pendingRouteStore.pending,
           PendingRouteLogic.fingerprint(existing.legs) != offer.fingerprint {
            shareReplaceOffer = offer
            return
        }
        proceedWithSharedRoute(offer)
    }

    func confirmReplaceSharedRoute() {
        guard let offer = shareReplaceOffer else { return }
        shareReplaceOffer = nil
        proceedWithSharedRoute(offer)
    }

    func dismissReplaceSharedRoute() {
        shareReplaceOffer = nil
    }

    /// Bypass the nearby flow: show the leg's origin as the sole station and
    /// fetch its board; the fetch completion decides track-now vs save-for-later.
    private func proceedWithSharedRoute(_ offer: SharedRouteOffer) {
        let now = Int(Date().timeIntervalSince1970)
        guard let index = offer.route.targetRideLegIndex(now: now) else {
            shareStatus = "This trip is already underway or finished"
            return
        }
        let leg = offer.route.legs[index]
        guard let stationId = leg.originId else {
            shareStatus = "Couldn't read this trip link"
            return
        }
        pendingShareTrack = offer
        launchStation(id: stationId, name: leg.originName, lat: leg.originLat, lon: leg.originLon)
    }

    /// Make a specific station the current one without a nearby search. Does NOT
    /// touch appState or the departure list, the caller decides whether to show
    /// the board (fresh share) or go straight to a countdown (explicit track).
    /// Leaves lastSearchCoordinate at the user's real GPS origin, not this remote
    /// station, so walk distances and recovery use where they are.
    private func setLaunchedStation(id: String, name: String?, lat: Double?, lon: Double?) {
        lastInteractionTime = Date()
        if appState == 3 { resumeFromInactive() }
        let station = Station(
            id: id, name: name ?? "Station", lat: lat, lon: lon,
            mode: currentMode, dist: nil, embeddedDepartures: nil
        )
        switch currentMode {
        case .train: trainStations = [station]
        case .bus: busStations = [station]
        case .tram: tramStations = [station]
        case .special: specialStations = [station]
        }
        if !availableModes.contains(currentMode) { availableModes = [currentMode] }
        stationIndex = 0
        launchedStationActive = true
    }

    /// Fresh-share intake: show the origin board and let the fetch decide
    /// track-now vs save-for-later. Blanks the list to a spinner while it loads.
    private func launchStation(id: String, name: String?, lat: Double?, lon: Double?) {
        setLaunchedStation(id: id, name: name, lat: lat, lon: lon)
        appState = 0
        departures = []
        favouriteDepartures = []
        fetchDepartures(stationId: id)
    }

    /// Leave a launched (remote) station and go back to the nearby list at the
    /// user's real location. No-op when the current station already came from a
    /// nearby search, so the normal tracking-exit path is unchanged.
    private func returnToNearbyIfLaunched() {
        guard launchedStationActive else { return }
        launchedStationActive = false
        trainStations = []
        busStations = []
        tramStations = []
        specialStations = []
        stationIndex = 0
        departures = []
        favouriteDepartures = []
        let coord = location.coordinate ?? lastSearchCoordinate
        if let coord, SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) {
            fetchStations(lat: coord.latitude, lon: coord.longitude)
        }
        // No coord yet: stations are empty, so the next location update fetches.
    }

    /// Runs on the departures fetch a shared route triggered: train on the
    /// board → track it now, keeping the route stored for leg advancement;
    /// not there yet → queue it and say so.
    @MainActor
    private func tryEnterPendingShareTrack() async {
        guard let offer = pendingShareTrack else { return }
        pendingShareTrack = nil
        let now = Int(Date().timeIntervalSince1970)
        let forced = offer.forceLegIndex
        guard let index = forced ?? offer.route.targetRideLegIndex(now: now),
              index >= 0, index < offer.route.legs.count else { return }
        let leg = offer.route.legs[index]
        let pending = pendingFor(offer, index: index)
        if let match = matchDeparture(departures, leg: leg) {
            // On the live board: track it with real delay/platform.
            var tracking = pending
            tracking.status = PendingRoute.statusTracking
            pendingRouteStore.save(tracking)
            PendingRouteNotifier.schedule(pending, now: now)
            selectDepartureImpl(match)
        } else if leg.isTrackable, forced != nil || PendingRouteLogic.isResumable(pending, now: now) {
            // Not on the board yet, but the user explicitly opened it (forced),
            // or it's close enough to resume: open a local countdown that
            // survives until the train departs. Never wall the user out.
            var tracking = pending
            tracking.status = PendingRoute.statusTracking
            pendingRouteStore.save(tracking)
            PendingRouteNotifier.schedule(pending, now: now)
            enterProtectedTrack(leg)
        } else {
            // Far out or untrackable (e.g. outside Switzerland): queue + remind.
            saveOfferAsQueued(offer)
        }
    }

    /// Preserve an existing route's id + muted legs when resuming/tracking it;
    /// a fresh share mints a new PendingRoute.
    private func pendingFor(_ offer: SharedRouteOffer, index: Int) -> PendingRoute {
        if let existing = offer.existing {
            var next = existing
            next.cursor = index
            return next
        }
        let now = Int(Date().timeIntervalSince1970)
        return PendingRoute.from(
            route: offer.route, targetLegIndex: index,
            id: UUID().uuidString, createdTs: now, sourceUrl: offer.sourceUrl
        )
    }

    private func saveOfferAsQueued(_ offer: SharedRouteOffer) {
        let now = Int(Date().timeIntervalSince1970)
        guard let index = offer.forceLegIndex ?? offer.route.targetRideLegIndex(now: now) else { return }
        var pending = pendingFor(offer, index: index)
        pending.status = PendingRoute.statusSaved
        pendingRouteStore.save(pending)
        PendingRouteNotifier.schedule(pending, now: now)
        shareStatus = "Saved. We'll remind you before departure"
        // Don't strand the user on the remote origin board. The queued route
        // lives in the chip now. Return to their real location.
        returnToNearbyIfLaunched()
    }

    // MARK: - Pending-route lifecycle
    // Normalize against the clock, expire, prompt. Safe to call from
    // anywhere, advancement is time-derived and idempotent.

    @MainActor
    func refreshPendingRoute() async {
        guard let current = pendingRouteStore.pending else { return }
        let now = Int(Date().timeIntervalSince1970)
        guard let normalized = PendingRouteLogic.normalize(current, now: now) else {
            pendingRouteStore.clear()
            PendingRouteNotifier.cancel()
            shareStatus = "Saved route to \(current.finalDestination) has passed"
            return
        }
        if normalized != current {
            pendingRouteStore.save(normalized)
            PendingRouteNotifier.schedule(normalized, now: now)
        }
        if appState != 2,
           normalized.status != PendingRoute.statusTracking,
           PendingRouteLogic.isResumable(normalized, now: now) {
            await offerResume(normalized)
        }
    }

    /// One-shot board check for the resume prompt, outside the normal fetch
    /// machinery so it can't disturb the visible station.
    @MainActor
    private func offerResume(_ route: PendingRoute) async {
        guard !resumeCheckInFlight, resumeOffer == nil,
              let leg = route.currentLeg, let stationId = leg.originId else { return }
        resumeCheckInFlight = true
        defer { resumeCheckInFlight = false }
        guard let result = try? await TrainAPIService.fetchDepartures(stationId: stationId) else { return }
        resumeOffer = matchDeparture(result.departures, leg: leg)
    }

    /// Notification tap / resume dialog Track / route-view "Track now" on the
    /// current leg. An explicit resume always opens the countdown, even hours
    /// out. A live board match gives real delay/platform, otherwise a local
    /// countdown. Never re-queues.
    func resumePendingRoute() {
        guard let route = pendingRouteStore.pending else { return }
        resumeOffer = nil
        let now = Int(Date().timeIntervalSince1970)
        guard let normalized = PendingRouteLogic.normalize(route, now: now) else {
            Task { @MainActor in await refreshPendingRoute() }
            return
        }
        trackLegImpl(normalized, index: normalized.cursor)
    }

    /// Route-view "Track now" on any trackable leg (may jump ahead to a later
    /// connection). Untrackable legs (walk / outside Switzerland) are ignored.
    func trackLeg(_ index: Int) {
        guard let route = pendingRouteStore.pending else { return }
        resumeOffer = nil
        let now = Int(Date().timeIntervalSince1970)
        guard let normalized = PendingRouteLogic.normalize(route, now: now) else {
            Task { @MainActor in await refreshPendingRoute() }
            return
        }
        trackLegImpl(normalized, index: index)
    }

    /// The countdown is fully local (derived from the leg's departure time), so
    /// an explicit tap enters it immediately: no board fetch gates it, the screen
    /// never blanks, and a slow or failed network can't bounce the user back to
    /// their location. The origin becomes the current station so walk distance,
    /// formation and live enrichment target it; beginTracking's timer then fetches
    /// that board in the background to upgrade platform/delay when it appears.
    private func trackLegImpl(_ route: PendingRoute, index: Int) {
        guard index >= 0, index < route.legs.count else { return }
        let leg = route.legs[index]
        guard leg.isTrackable, let stationId = leg.originId else { return }
        var pending = route
        pending.cursor = index
        pending.status = PendingRoute.statusTracking
        pendingRouteStore.save(pending)
        let now = Int(Date().timeIntervalSince1970)
        PendingRouteNotifier.schedule(pending, now: now)
        setLaunchedStation(id: stationId, name: leg.originName, lat: leg.originLat, lon: leg.originLon)
        enterProtectedTrack(leg)
    }

    /// Route-view per-leg track/notify toggle. Reschedules the reminder so a
    /// muted current leg drops its notification, an un-muted one restores it.
    func setLegMuted(_ index: Int, muted: Bool) {
        pendingRouteStore.setLegMuted(index, muted: muted)
        let now = Int(Date().timeIntervalSince1970)
        if let route = pendingRouteStore.pending {
            PendingRouteNotifier.schedule(route, now: now)
        }
    }

    /// Platform per ride leg for the route view, keyed by leg index. Platforms
    /// aren't in the shared link, they come from the live board and only exist
    /// close to departure, so this fetches each near-term leg's origin board
    /// once and matches it. Legs hours out simply have no platform yet.
    @Published var routeLegPlatforms: [Int: String] = [:]

    func loadRoutePlatforms(_ route: PendingRoute) {
        routeLegPlatforms = [:]
        Task { @MainActor in
            let now = Int(Date().timeIntervalSince1970)
            var result: [Int: String] = [:]
            for (index, leg) in route.legs.enumerated() {
                guard leg.type == .ride, leg.isTrackable else { continue }
                guard leg.depTs - now <= 60 * 60 else { continue } // not on the board yet
                guard let stationId = leg.originId else { continue }
                guard let board = try? await TrainAPIService.fetchDepartures(stationId: stationId) else { continue }
                if let platform = matchDeparture(board.departures, leg: leg)?.platform, !platform.isEmpty {
                    result[index] = platform
                }
            }
            routeLegPlatforms = result
        }
    }

    /// While tracking a shared-route leg, the next ride leg of the same route is
    /// the onward connection: shown under the countdown, tappable to jump onto
    /// it early. Matched by departure time so an unrelated track shows nothing.
    var onwardConnection: OnwardConnection? {
        guard let focused = focusedTrain, let route = pendingRouteStore.pending else { return nil }
        guard let curIdx = route.legs.firstIndex(where: {
            $0.type == .ride && $0.depTs == focused.departureTimestamp
        }) else { return nil }
        let curLeg = route.legs[curIdx]
        guard let nextIdx = route.legs[(curIdx + 1)...].firstIndex(where: { $0.type == .ride }) else { return nil }
        let next = route.legs[nextIdx]
        let changeMinutes = max(0, (next.depTs - curLeg.arrTs) / 60)
        return OnwardConnection(changeStation: curLeg.destName, leg: next, legIndex: nextIdx, changeMinutes: changeMinutes)
    }

    func deferResume() {
        resumeOffer = nil
    }

    func dismissPendingRoute() {
        resumeOffer = nil
        pendingRouteStore.clear()
        PendingRouteNotifier.cancel()
    }

    /// A tracking session ended (departed or user-exited). The route only
    /// reacts when it was tracking that exact departure: post-departure it
    /// advances to the next leg, an early exit reverts to saved.
    private func onTrackingEnded(_ endedDepTs: Int?) {
        guard let endedDepTs, let current = pendingRouteStore.pending else { return }
        let now = Int(Date().timeIntervalSince1970)
        let next = PendingRouteLogic.advancedAfterTracking(current, endedDepTs: endedDepTs, now: now)
        if let next {
            if next != current {
                pendingRouteStore.save(next)
                PendingRouteNotifier.schedule(next, now: now)
            }
        } else {
            pendingRouteStore.clear()
            PendingRouteNotifier.cancel()
        }
    }
}

/// A decoded shared route awaiting a decision (auto-track, queue, or the
/// user's replace confirmation). forceLegIndex + existing are set when resuming
/// or tracking a leg the user already saved: force enters tracking regardless of
/// the resume window, and existing preserves the stored id + muted legs.
struct SharedRouteOffer {
    let route: SharedRoute
    let sourceUrl: String?
    var forceLegIndex: Int? = nil
    var existing: PendingRoute? = nil

    var fingerprint: String { PendingRouteLogic.fingerprint(route.legs) }
}

/// The next ride leg while tracking a shared route: where the user changes, the
/// onward train, and the connection buffer in minutes.
struct OnwardConnection {
    let changeStation: String
    let leg: RouteLeg
    let legIndex: Int
    let changeMinutes: Int
}
