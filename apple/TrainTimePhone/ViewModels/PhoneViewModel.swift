import ActivityKit
import SwiftUI
import CoreLocation
import Combine
import Foundation
import WidgetKit

class PhoneViewModel: ObservableObject {
    // Shown (and used as the gate for the faint Swiss-outline backdrop) when the phone is
    // located outside Switzerland with no stations to show.
    static let outOfBoundsStatus = String(localized: "Not in Switzerland")

    // MARK: - Services
    let location = PhoneLocationService()
    private var locationCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var favouritesCancellable: AnyCancellable?

    // MARK: - App State
    @Published var appState: Int = 0 // 0=station view, 2=focused tracking, 3=inactive
    @Published var showReviewPrompt = false // timed review ask (Yes / Not now / Don't ask again)
    @Published var openWriteReviewTick = 0 // a watch asked to rate; the view opens the write-review page
    @Published var status: String = String(localized: "GPS: Searching...")

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
    let watchService = PhoneWatchService.shared
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
    // Ping-gate bookkeeping, persisted across launches: the freshest Garmin signal
    // ever heard (bye does not zero it, unlike garminLastAlive), the last bye, and
    // the watch's protocol version. Together they say "the watch app is probably
    // still open", the only case where a foreground ping is safe.
    private var garminLastAliveHighWater =
        Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "garminLastAliveTs"))
    private var garminLastByeAt =
        Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "garminLastByeTs"))
    private var garminWatchPv = UserDefaults.standard.integer(forKey: "garminWatchPv")
    // Version last announced by each backend (nil until first heard). Drives the
    // Send-to-Watch update guard; a pre-versioning watch reports 0.4.x.
    private var garminWatchVersion: String?
    private var appleWatchVersion: String?
    private var livenessTimer: AnyCancellable?
    // Bumped by the liveness ticker so the time-based indicator recomputes on each render.
    @Published private var livenessTick = 0
    // A Garmin open attempt is in flight (spinner). Apple can't be launched, so it's Garmin-only.
    @Published var watchChecking = false
    // Departure a watch reports it is tracking: set by trackStarted and by trk/trkLn
    // on the state-carrying liveness heartbeat (Garmin pv>=3, Apple pv>=2), cleared
    // by trackEnded and bye; validity additionally requires the owning backend to be
    // alive. This is what flips "Track on watch" to "Tracking on watch".
    @Published private(set) var watchTrackingDepTs: Int?
    @Published private(set) var watchTrackingLine: String?
    // Full trackStarted payload when we saw one (the heartbeat only carries
    // depTs/line). Needed to rebuild a FocusedDeparture for tap-to-follow.
    private var watchTrackingInfo: [String: Any]?
    private var watchTrackingSource: PhoneWatchType?
    private var appleWatchPv = 0
    // The user asked to track on a closed watch: openWatchApp is in flight and the
    // next hello must carry the track command first. Without this, a stale alive
    // reading used to route the tap into a send the closed app never saw.
    private var pendingWatchTrackSend = false

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
    // Last GPS tier handed to CoreLocation while tracking, so the tier is only
    // re-applied when it actually changes (not every 1 s tick). Nil = not tracking.
    private var lastLocationTier: LocationTier?

    // MARK: - Deep link pending
    private var pendingDeepLink: URL?

    // MARK: - Shared SBB route intake
    // pendingShareTrack is one-shot: the departures fetch it triggered
    // consumes it, so an unrelated board can't auto-track.
    let pendingRouteStore = PendingRouteStore.shared
    @Published var shareStatus: String? = nil
    @Published var shareReplaceOffer: SharedRouteOffer? = nil
    private var pendingShareTrack: SharedRouteOffer?

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
        currentStation?.name ?? String(localized: "Station")
    }

    // MARK: - Init

    private var stopObserver: NSObjectProtocol?

    init() {
        reviewStore.ensureFirstLaunchTimestamp()
        // A process death mid-tracking strands the Live Activity; no session can
        // exist yet, so anything found is an orphan.
        reapOrphanLiveActivities()

        // The Live Activity's Stop button (a LiveActivityIntent running in-process)
        // posts here — the analog of Android's notification Stop → stopRequests.
        stopObserver = NotificationCenter.default.addObserver(
            forName: .stopTrackingRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleStopFromLiveActivity() }
        }

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
            .sink { [weak self] favourites in
                guard let self else { return }
                self.favouriteDepartures = self.extractFavouritesFromCurrent(self.departures)
                // The Apple Watch syncs favourites over WCSession in FavouritesStore;
                // Garmin needs an explicit push for the outer-join (no-op if closed).
                self.send(PhoneWatchService.GarminPayload.favourites(favourites), to: .garmin)
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
            let kind = context["kind"] as? String
            // Any Garmin message but the liveness kinds still proves the watch app
            // is open: a saveReminder or favourites push greens the indicator and
            // unblocks the alive-gated sends. hello/alive refresh inside markAlive
            // (which needs the pre-refresh state for its transition sync).
            if source == .garmin, let k = kind, !["hello", "alive", "bye"].contains(k) {
                self.garminLastAlive = Date()
                self.garminLastAliveHighWater = self.garminLastAlive
            }
            switch kind {
            case "hello", "alive":
                self.markAlive(source, context: context)
            case "bye":
                self.markBye(source)
            case "reqLoc":
                self.replyWithLocation(to: source)
            case "rateApp":
                // The watch has no review page of its own; open ours.
                self.openWriteReviewTick += 1
            case "saveReminder":
                // The watch (Apple or Garmin) asked us to save its focused
                // departure as a reminder; schedule it like a board save.
                self.saveReminderFromWatch(context, source: source)
            case "favourites":
                // The Garmin watch pushed its favourites: outer-join them into ours.
                self.applyGarminFavourites(context["favs"])
            case "trackStarted":
                // The watch entered tracking (its own tap, or the echo of our
                // track command — the echo doubles as the delivery ack).
                self.watchTrackingDepTs = self.intValue(context["depTs"])
                self.watchTrackingLine = context["line"] as? String
                self.watchTrackingInfo = context
                self.watchTrackingSource = source
            case "trackEnded":
                if self.watchTrackingSource == source || self.watchTrackingSource == nil {
                    self.clearWatchTracking()
                }
            default:
                self.applyReceivedWatchContext(context)
            }
        }
    }

    // Reconstruct the one-leg route the watch described and queue it for a reminder.
    // Coords are required (the distance-aware reminder needs them); numbers may
    // arrive as Int or Double across the WCSession / Connect IQ bridges.
    private func saveReminderFromWatch(_ context: [String: Any], source: PhoneWatchType) {
        func intOf(_ key: String) -> Int? {
            if let i = context[key] as? Int { return i }
            if let d = context[key] as? Double { return Int(d) }
            return nil
        }
        func doubleOf(_ key: String) -> Double? {
            if let d = context[key] as? Double { return d }
            if let i = context[key] as? Int { return Double(i) }
            return nil
        }
        guard let dest = context["dest"] as? String,
              let depTs = intOf("depTs"),
              let line = context["line"] as? String,
              let stId = context["stId"] as? String,
              let lat = doubleOf("lat"), let lon = doubleOf("lon") else { return }
        // Ack receipt (not save) as soon as the payload parses, so the Garmin
        // watch can clear its outbox: retries of the same id land here
        // idempotently. Not through send() (alive-gated, mirror-gated) — an ack
        // must always answer. An old watch sends no id and expects no ack.
        if source == .garmin, let id = context["id"] as? String {
            watchService.sendToGarminWatches(PhoneWatchService.GarminPayload.ackReminder(id: id))
        }
        let route = SharedRoute.single(
            originId: stId,
            originName: context["stName"] as? String ?? String(localized: "Station"),
            originLat: lat, originLon: lon,
            destName: dest, depTs: depTs,
            lineNumber: line, trainNumber: context["trainNum"] as? String
        )
        saveExternalRouteAsPending(route)
    }

    // Outer-join the Garmin watch's favourites into ours. The store change re-pushes
    // the merged set (Apple Watch over WCSession, Garmin via the favourites observer);
    // the Garmin watch unions and never re-broadcasts, so this converges loop-free.
    private func applyGarminFavourites(_ raw: Any?) {
        guard let items = raw as? [[String: Any]] else { return }
        let incoming: [Favourite] = items.compactMap { m in
            guard let stId = m["stId"] as? String,
                  let line = m["line"] as? String,
                  let dest = m["dest"] as? String else { return nil }
            return Favourite(stationId: stId, stationName: m["name"] as? String ?? stId,
                             lineNumber: line, destination: dest)
        }
        let merged = FavouritesStore.union(favouritesStore.favourites, incoming)
        if merged != favouritesStore.favourites {
            favouritesStore.replaceAll(with: merged)
        }
    }

    // A backend just announced it's open. Refresh its freshness and, on the transition into
    // alive, push the phone's current view so the watch jumps straight to it.
    private func markAlive(_ source: PhoneWatchType, context: [String: Any]) {
        // A pre-versioning watch sends no version: read as 0.4.x.
        let v = context["v"] as? String ?? WatchSyncProtocol.legacyVersionName
        switch source {
        case .garmin:
            garminWatchVersion = v
            garminWatchPv = context["pv"] as? Int ?? 0
            let wasAlive = garminAlive
            garminLastAlive = Date()
            garminLastAliveHighWater = garminLastAlive
            watchChecking = false
            applyLivenessTracking(context, source: .garmin, statefulPv: garminWatchPv >= 3)
            // A user-initiated track send takes priority and goes out first — it's
            // the time-critical payload. Otherwise the freshly-online watch jumps
            // to whatever the phone is showing.
            if pendingWatchTrackSend {
                pendingWatchTrackSend = false
                sendFocusedTrackFirst(to: .garmin)
            } else if !wasAlive {
                syncCurrentStateToWatch(to: .garmin)
            }
        case .appleWatch:
            appleWatchVersion = v
            appleWatchPv = context["pv"] as? Int ?? 0
            let wasAlive = appleAlive
            appleLastAlive = Date()
            appleLastContact = Date()
            applyLivenessTracking(context, source: .appleWatch, statefulPv: appleWatchPv >= 2)
            if pendingWatchTrackSend {
                pendingWatchTrackSend = false
                sendFocusedTrackFirst(to: .appleWatch)
            } else if !wasAlive {
                syncCurrentStateToWatch(to: .appleWatch)
            }
        }
    }

    private func markBye(_ source: PhoneWatchType) {
        if watchTrackingSource == source { clearWatchTracking() }
        switch source {
        case .garmin:
            // The high water mark stays: bye after alive is exactly what the
            // ping gate reads.
            garminLastAlive = .distantPast
            garminLastByeAt = Date()
            persistGarminLinkState()
        case .appleWatch:
            appleLastAlive = .distantPast
            appleLastContact = Date()
        }
    }

    private func persistGarminLinkState() {
        UserDefaults.standard.set(garminLastAliveHighWater.timeIntervalSince1970, forKey: "garminLastAliveTs")
        UserDefaults.standard.set(garminLastByeAt.timeIntervalSince1970, forKey: "garminLastByeTs")
        UserDefaults.standard.set(garminWatchPv, forKey: "garminWatchPv")
    }

    // MARK: - Watch tracking state

    private func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    private func clearWatchTracking() {
        watchTrackingDepTs = nil
        watchTrackingLine = nil
        watchTrackingInfo = nil
        watchTrackingSource = nil
    }

    // trk/trkLn on a hello/alive mirror the tracked departure; their absence on a
    // watch whose pv promises state means "not tracking". Older watches stay
    // edge-driven (trackStarted only), so silence doesn't clear them here.
    private func applyLivenessTracking(_ context: [String: Any], source: PhoneWatchType, statefulPv: Bool) {
        if let trk = intValue(context["trk"]) {
            if intValue(watchTrackingInfo?["depTs"]) != trk { watchTrackingInfo = nil }
            watchTrackingDepTs = trk
            watchTrackingLine = context["trkLn"] as? String
            watchTrackingSource = source
        } else if statefulPv, watchTrackingSource == source {
            clearWatchTracking()
        }
    }

    /// A watch claims to be tracking and its liveness is fresh — a dead heartbeat
    /// takes the claim with it, so this can never show stale state.
    var watchTrackingActive: Bool {
        guard watchTrackingDepTs != nil, let src = watchTrackingSource else { return false }
        switch src {
        case .garmin: return garminAlive
        case .appleWatch: return appleAlive
        }
    }

    /// The watch is tracking the same departure the phone is focused on.
    var watchTrackingFocused: Bool {
        guard watchTrackingActive, let focused = focusedTrain, let depTs = watchTrackingDepTs else { return false }
        if let line = watchTrackingLine, !line.isEmpty, line != focused.lineNumber { return false }
        return focused.departureTimestamp == depTs
    }

    /// "IC 8 → Brig · 14:54" for the board-view chip; built from the last
    /// trackStarted payload, or just line + time when only the heartbeat spoke.
    var watchTrackingLabel: String? {
        guard watchTrackingActive, let depTs = watchTrackingDepTs else { return nil }
        let infoLine = (watchTrackingInfo?["line"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let line = infoLine ?? watchTrackingLine.flatMap { $0.isEmpty ? nil : $0 }
        let dest = (watchTrackingInfo?["dest"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let time = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(depTs)))
        var head: [String] = []
        if let line { head.append(line) }
        if let dest { head.append("→ \(dest)") }
        return head.isEmpty ? time : "\(head.joined(separator: " ")) · \(time)"
    }

    var watchTrackingFollowable: Bool {
        guard watchTrackingActive, let info = watchTrackingInfo else { return false }
        return intValue(info["depTs"]) == watchTrackingDepTs && !((info["dest"] as? String) ?? "").isEmpty
    }

    /// Enter the phone's tracking view on the departure the watch is tracking,
    /// without mirroring back (the watch already owns this track).
    func followWatchTracking() {
        guard let depTs = watchTrackingDepTs, let info = watchTrackingInfo,
              intValue(info["depTs"]) == depTs,
              let dest = info["dest"] as? String, !dest.isEmpty else { return }
        beginTracking(FocusedDeparture(
            destination: dest,
            departureTimestamp: depTs,
            lineNumber: info["line"] as? String ?? "",
            category: info["cat"] as? String ?? "",
            trainNumber: info["trainNum"] as? String,
            operatorRef: info["opRef"] as? String,
            delay: intValue(info["delay"]) ?? 0,
            platform: info["plat"] as? String ?? "",
            platformChanged: info["platChg"] as? Bool ?? false
        ), mirror: false)
    }

    // Accelerate the green indicator when the phone foregrounds while the watch
    // app is probably still open: ask it to say hello now instead of waiting out
    // its heartbeat. Deliberately not through send() (alive-gated) — the
    // WatchSyncProtocol gate is the safety here.
    private func maybePingGarmin() {
        guard mirrorToWatch, watchService.hasGarminWatch, !garminAlive else { return }
        guard WatchSyncProtocol.shouldPingGarmin(
            lastAlive: garminLastAliveHighWater,
            lastBye: garminLastByeAt,
            now: Date(),
            pv: garminWatchPv
        ) else { return }
        watchService.sendToGarminWatches(PhoneWatchService.GarminPayload.ping())
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

    /// Absolute epoch-second the reminder will fire for the active route, for the
    /// green "notified in X min" line on the pending-route chip. Nil when none.
    @Published var reminderNotifyTs: Int?

    /// The reminder split into walk + buffer for the chip's coloured readout.
    @Published var reminderPlan: NotifyPlan?

    /// Start/stop background distance tracking to match settings + the current
    /// route, and refresh the in-app notify countdown. The SLC monitor lives in
    /// ReminderTracker so it survives relaunch.
    func syncReminderTracking() {
        ReminderTracker.shared.syncFromSettings()
        refreshReminderPlan()
    }

    /// The user's background-tracking switch. Defaults on, matching Android.
    var backgroundTrackingEnabled: Bool {
        UserDefaults.standard.object(forKey: "backgroundReminderTracking") as? Bool ?? true
    }

    /// Turning background tracking off is immediate and total: the Live Activity
    /// goes, a parked background session goes with it, and background location
    /// stops. Tracking then only runs while the app is open.
    func disableBackgroundTracking() {
        backgroundTracked = nil
        backgroundTrackedStation = nil
        PendingRouteNotifier.cancelApproachAlert()
        endLiveActivity(departed: false)
        if appState != 2 { location.setTrackingAccuracy(false) }
        syncReminderTracking()
    }

    // MARK: - Background-location introduction

    /// One-shot introduction of the optional background-location upgrade for
    /// saved-route reminders, shown once when a version carrying the feature
    /// first runs. Only offered from When-In-Use, the sole state where iOS can
    /// still show the Always upgrade prompt. Declining changes nothing:
    /// reminders keep using the last known location. Mirrors the Android intro.
    @Published var showBgLocationIntro = false

    private func maybeShowBgLocationIntro() {
        guard !UserDefaults.standard.bool(forKey: "bgLocationIntroSeen"),
              ReminderTracker.shared.canPromptForAlways else { return }
        showBgLocationIntro = true
    }

    func acceptBgLocationIntro() {
        showBgLocationIntro = false
        UserDefaults.standard.set(true, forKey: "bgLocationIntroSeen")
        ReminderTracker.shared.requestAlwaysPermission()
    }

    func dismissBgLocationIntro() {
        showBgLocationIntro = false
        UserDefaults.standard.set(true, forKey: "bgLocationIntroSeen")
    }

    /// The route sheet's note: distance-aware timing is on but the grant is
    /// missing, so the lead is pinned to the save-time location.
    var reminderNeedsBgLocation: Bool {
        UserDefaults.standard.bool(forKey: "distanceAwareReminder") &&
            !ReminderTracker.shared.hasAlwaysPermission
    }

    /// The route sheet's "Enable background location" link. When-In-Use can
    /// still trigger the real prompt; any other state only resolves in Settings.
    func enableBackgroundLocation() {
        if ReminderTracker.shared.canPromptForAlways {
            ReminderTracker.shared.requestAlwaysPermission()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Recompute the chip's notify plan (no SLC toggling). Called on every live
    /// fix so the walk readout tracks the routed measurement as the user moves.
    private func refreshReminderPlan() {
        let plan = pendingRouteStore.pending.flatMap { PendingRouteNotifier.nextNotifyPlan(for: $0) }
        reminderPlan = plan
        reminderNotifyTs = plan?.notifyTs
    }

    /// Measure the routed walk (MKDirections) from the live location to the saved
    /// route's origin and stash it for the notifier, so the chip and reminder lead
    /// use the same basis as tracking (not a shorter straight line). Falls back to
    /// the estimate when routed distance is off, there's no fix, or no origin.
    func updatePendingRouteWalk() {
        guard useRoutedDistance,
              UserDefaults.standard.bool(forKey: "distanceAwareReminder"),
              let route = pendingRouteStore.pending,
              let leg = route.currentLeg,
              let oLat = leg.originLat, let oLon = leg.originLon,
              let originId = leg.originId,
              let coord = location.coordinate else {
            refreshReminderPlan()
            return
        }
        let origin = CLLocationCoordinate2D(latitude: oLat, longitude: oLon)
        let haversine = GeoUtils.haversineDistance(from: coord, to: origin)
        // Fetch fresh for the origin (no useful pre-existing cache), refetching as
        // the user moves, exactly as tracking does for the focused station.
        if routing.shouldRefetch(stationId: originId, currentCoord: coord, currentHaversine: haversine) {
            Task { [weak self] in
                await self?.routing.fetchRoute(
                    from: coord, to: origin, stationId: originId, currentHaversine: haversine)
                await MainActor.run {
                    self?.commitPendingWalk(routeId: route.id, originId: originId, haversine: haversine)
                }
            }
        }
        commitPendingWalk(routeId: route.id, originId: originId, haversine: haversine)
    }

    /// Persist the routed walk seconds for the notifier's `routedWalkSec`, then
    /// refresh the chip. Nil interpolation (first fetch still in flight) leaves the
    /// straight-line estimate showing until the route lands.
    private func commitPendingWalk(routeId: String, originId: String, haversine: Double) {
        guard let routed = routing.interpolate(stationId: originId, currentHaversine: haversine) else {
            refreshReminderPlan()
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(routeId, forKey: "pendingWalkRouteId")
        defaults.set(Int(routed.time), forKey: "pendingWalkSec")
        defaults.set(Int(Date().timeIntervalSince1970), forKey: "pendingWalkTs")
        refreshReminderPlan()
    }

    /// Distance-aware test: computes the real distance from the current location
    /// to the active route's origin (or the nearest station) and reports the lead
    /// it would produce, immediately. Exercises the whole distance pipeline.
    func sendDistanceReminderTest() {
        let leg = pendingRouteStore.pending?.currentLeg
        let originLat = leg?.originLat ?? currentStation?.lat
        let originLon = leg?.originLon ?? currentStation?.lon
        let originName = leg?.originName ?? currentStation?.name
        guard let coord = location.coordinate, let originLat, let originLon, let originName else {
            PendingRouteNotifier.notify(
                title: String(localized: "Distance test"),
                body: String(localized: "Turn on location and open the app near a station first."))
            return
        }
        let dist = GeoUtils.haversineDistance(
            from: coord,
            to: CLLocationCoordinate2D(latitude: originLat, longitude: originLon))
        let walkMin = Int(GeoUtils.walkMinutes(distanceMeters: dist))
        let leadMinutes = UserDefaults.standard.integer(forKey: "routeReminderLeadMinutes")
        let savedLeadSec = (leadMinutes > 0 ? leadMinutes : 15) * 60
        let walkSec = Int(GeoUtils.walkMinutes(distanceMeters: dist) * 60)
        let leadMin = min(walkSec + savedLeadSec, PendingRouteLogic.maxLeadSec) / 60
        PendingRouteNotifier.notify(
            title: String(localized: "Distance test: \(originName)"),
            body: String(localized: "\(Int(dist)) m away (~\(walkMin) min walk). Reminder would fire \(leadMin) min before departure."))
    }

    func onAppear() {
        lastInteractionTime = Date()
        location.start()
        startTimer(interval: appState == 2 ? Timing.trackingRefreshInterval : Timing.normalRefreshInterval)
        watchService.initialize()
        startLivenessTicker()
        syncReminderTracking()
        maybeShowBgLocationIntro()
        // Feed an already-open watch the current location once device status has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshConnectedWatches()
            self?.pushLocationNow()
            self?.maybePingGarmin()
        }
    }

    func onDisappear() {
        updateWidgetCache() // the widget is only visible once we background; seed it with what was on screen
        persistGarminLinkState() // the ping gate must survive a kill while backgrounded
        livenessTimer?.cancel()
        livenessTimer = nil
        // An active tracking session keeps running in the background: continuous
        // location (UIBackgroundModes location) holds the process alive and the
        // fetch timer keeps the Live Activity honest. Requires the background
        // mode to actually be engaged, otherwise tear down exactly as before.
        // The user's switch is the outermost gate: off means the session ends
        // with the foreground, so nothing is held.
        if backgroundTrackingEnabled && appState == 2 && location.backgroundTrackingActive {
            return
        }
        location.stop()
        stopTimer()
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
                status = String(localized: "GPS: Searching...")
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
                if stations.isEmpty { status = String(localized: "Updating stations...") }
                fetchStations(lat: coord.latitude, lon: coord.longitude)
            }
            return
        }

        if stations.isEmpty && !requestInFlight {
            status = String(localized: "Finding stations...")
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

        // A parked background session has no tracking screen driving it, so this
        // tick is the only thing that can retire its card and Live Activity once
        // the train has gone. Without it the card sits at "0 min" and the Live
        // Activity survives to ActivityKit's own cap.
        if appState != 2, let parked = backgroundTracked, hasDeparted(parked) {
            backgroundTracked = nil
            backgroundTrackedStation = nil
            PendingRouteNotifier.cancelApproachAlert()
            endLiveActivity(departed: true)
        }

        // State 2: auto-exit check and heartbeat
        if appState == 2 {
            if let focused = focusedTrain {
                let minutesLeft = focused.minutesUntil
                // Departed past the grace, counting the live delay: drop to the inactive
                // tap-to-refresh state, not the station view, so polling stops right away.
                // The watch expires on its own depTs.
                if hasDeparted(focused) {
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
                updateLiveActivity()
            }
        }

        // Keep the saved-route chip + reminder lead on the live routed walk.
        updatePendingRouteWalk()

        // Inactivity timeout in station view
        if appState == 0, Date().timeIntervalSince(lastInteractionTime) >= Timing.inactivityTimeout {
            enterInactiveState()
            return
        }

        if appState == 3 { return }

        // Fetch cadence + GPS scale with proximity while immersive-tracking (§A):
        // far out polls rarely (or not at all when paused, letting the Live
        // Activity carry the countdown) with GPS idle; both tighten to 15–30 s and
        // precise GPS near departure. Board browsing keeps the normal 30 s cadence
        // regardless of any background-card session (that one is Live-Activity-only).
        let cooldown: TimeInterval
        if appState == 2, let focused = focusedTrain {
            let tier = TrackingTiers.pollTier(minutesUntil: focused.minutesUntil + Double(focused.delay))
            applyLocationTier(tier.location)
            // A held immersive screen must never freeze. The paused tier (>6h out)
            // has a nil interval; floor it to the far-tier cadence so a distant train
            // still refreshes while the user watches, instead of stalling forever.
            cooldown = tier.apiInterval ?? 900
        } else {
            cooldown = Timing.fetchCooldownNormal
        }

        if !requestInFlight, Date().timeIntervalSince(lastFetchTime) >= cooldown {
            if let station = currentStation, let id = station.id {
                fetchDepartures(stationId: id)
            } else if stations.isEmpty,
                      SwissBounds.contains(lat: coord.latitude, lon: coord.longitude) {
                fetchStations(lat: coord.latitude, lon: coord.longitude)
            }
        }
    }

    /// Re-point CoreLocation only when the proximity tier actually changes, so a
    /// tracked session doesn't reconfigure the manager every tick.
    private func applyLocationTier(_ tier: LocationTier) {
        guard lastLocationTier != tier else { return }
        lastLocationTier = tier
        location.setTrackingAccuracy(true, tier: tier)
    }

    // MARK: - Departure Selection & Tracking

    func selectFavouriteDeparture(_ dep: Departure) {
        selectDepartureImpl(dep)
    }

    func selectDeparture(index: Int) {
        guard index >= 0, index < departures.count else { return }
        selectDepartureImpl(departures[index])
    }

    private func selectDepartureImpl(_ dep: Departure, routeDestination: String? = nil) {
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
            platformChanged: dep.platformChanged,
            routeDestination: routeDestination
        ))
        // Only a real board tap counts toward the review ask.
        maybeRequestReview()
    }

    /// Track a shared-route leg whose train isn't on the live board yet. The
    /// countdown is fully local (derived from depTs), so it runs without a board
    /// match. updateFocusedTrain keeps it until the train actually departs, then
    /// a live board match upgrades it with delay/platform.
    private func enterProtectedTrack(_ leg: RouteLeg, routeDestination: String? = nil) {
        beginTracking(FocusedDeparture(
            // Best-effort until a live board match upgrades it to the train's real
            // terminus; the leg only carries its alight stop.
            destination: leg.destName,
            departureTimestamp: leg.depTs,
            lineNumber: leg.lineNumber ?? "",
            category: leg.category ?? "",
            trainNumber: leg.trainNumber,
            operatorRef: nil,
            delay: 0,
            platform: "",
            platformChanged: false,
            routeDestination: routeDestination
        ))
    }

    /// Shared tracking entry: from a real board tap or a synthesised shared-route
    /// leg. Everything downstream (timer cadence, watch/Garmin mirror, formation)
    /// is identical once we have a FocusedDeparture. mirror=false when following
    /// a track the watch already owns — re-sending it would make the watch
    /// re-enter (and re-buzz) its own tracking.
    private func beginTracking(_ focused: FocusedDeparture, mirror mirrorToWatches: Bool = true) {
        // Only one session exists at a time. Tracking something new retires any
        // parked background session, otherwise the board keeps a card for a
        // train whose Live Activity startLiveActivity is about to replace, and
        // its leave alert would still fire.
        if backgroundTracked != nil {
            backgroundTracked = nil
            backgroundTrackedStation = nil
            PendingRouteNotifier.cancelApproachAlert()
        }
        focusedTrain = focused
        appState = 2
        location.setTrackingAccuracy(true)
        lastLocationTier = .high
        consecutiveErrors = 0
        lastVibeTick = 0
        lastFetchTime = .distantPast
        formation = nil

        // Lock Screen / Dynamic Island session; survives the app backgrounding.
        startLiveActivity(focused)

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
        if mirrorToWatches {
            mirror(PhoneWatchService.GarminPayload.track(focused, station: currentStation))
        }
    }

    func enterInactiveState() {
        onTrackingEnded(appState == 2 ? focusedTrain?.departureTimestamp : nil)
        if appState == 2 {
            // Departed auto-exit keeps a final "Departed" card up briefly;
            // a plain timeout dismisses straight away.
            endLiveActivity(departed: focusedTrain.map(hasDeparted) ?? false)
        }
        appState = 3
        location.setTrackingAccuracy(false)
        lastLocationTier = nil
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
            stationName: station.name ?? String(localized: "Station"),
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

    /// Stop requested from the Live Activity button (see `StopTrackingIntent`).
    /// An immersive session drops to the board; a background-card session tears down.
    func handleStopFromLiveActivity() {
        if appState == 2 {
            exitToStationView()
        } else if backgroundTracked != nil {
            stopBackgroundTracking()
        }
    }

    func exitToStationView() {
        let wasTracking = appState == 2
        onTrackingEnded(wasTracking ? focusedTrain?.departureTimestamp : nil)
        if wasTracking { endLiveActivity(departed: false) }
        // A queued "track on watch" intent dies with the tracking session.
        pendingWatchTrackSend = false
        lastInteractionTime = Date()
        appState = 0
        location.setTrackingAccuracy(false)
        lastLocationTier = nil
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
            let name = st.name ?? String(localized: "Station")
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
        status = String(localized: "Finding stations...")
    }

    // MARK: - Focused Train Update

    private func updateFocusedTrain() {
        guard var focused = focusedTrain else { return }

        // Match by train number when we have one (a protected shared-route leg
        // carries it), so live platform/delay are adopted even though the leg's
        // destName is the alight stop, not the board's terminus. Fall back to
        // destination for board taps that lack a train number (buses/trams).
        // minutesUntil is scheduled, so the delay has to be added or a late
        // train drops off the board a minute after its scheduled time and the
        // effective-departure grace below never gets a chance to run.
        let matches = departures.filter {
            ($0.destination == focused.destination ||
                (focused.trainNumber != nil && $0.trainNumber == focused.trainNumber)) &&
                Double($0.minutesUntil) + Double($0.delay) >= -1
        }
        guard let best = matches.min(by: {
            abs(Double($0.minutesUntil) - focused.minutesUntil) <
            abs(Double($1.minutesUntil) - focused.minutesUntil)
        }) else {
            // A still-future train just isn't on the board yet (a shared route
            // opened early, before it reaches the 20-row horizon). Keep the
            // local countdown; only give up once it has actually departed.
            let nowS = Int(Date().timeIntervalSince1970)
            let effectiveDep = focused.departureTimestamp + focused.delay * 60
            if nowS < effectiveDep + PendingRouteLogic.graceSec { return }
            PhoneHapticService.shortPulse()
            exitToStationView()
            return
        }

        let oldPlatform = focused.platform
        var platformSwitched = false
        if best.platform != oldPlatform && !best.platform.isEmpty {
            if best.platformChanged {
                PhoneHapticService.doublePulse()
                platformSwitched = true
            }
            focused.platform = best.platform
            focused.platformChanged = best.platformChanged
        }

        // A protected route leg starts with the leg's alight stop; the live board
        // row carries the train's real terminus, so adopt it. Board taps already
        // match on destination, so this is a no-op for them.
        if !best.destination.isEmpty && best.destination != focused.destination {
            focused.destination = best.destination
        }

        focused.delay = best.delay
        focusedTrain = focused
        // A platform switch banners the Live Activity, the double pulse's
        // lock-screen analog.
        updateLiveActivity(alertPlatformChange: platformSwitched)
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
        // Cached coordinates prove nothing about where we are now: computing an
        // ahead/behind verdict from one produced the "800 min behind" failure
        // when the seed was a city away.
        if gpsQuality == .unavailable || gpsQuality == .lastKnown { return String(localized: "No GPS") }
        let absBuf = abs(buf)
        if absBuf < 0.5 { return String(localized: "On time") }
        let unit = absBuf < 1.5 ? "\(Int(absBuf * 60))s" : String(localized: "\(Int(absBuf)) min")
        return buf > 0 ? String(localized: "\(unit) ahead") : String(localized: "\(unit) behind")
    }

    var trackingStatusColor: Color {
        let buf = trackingEffectiveBuffer
        if gpsQuality == .unavailable || gpsQuality == .lastKnown { return AppColors.barGray }
        if buf > 0.5 { return AppColors.ahead }
        if buf < -0.5 { return AppColors.behind }
        return AppColors.onTime
    }

    // MARK: - Live Activity

    private var liveActivity: Activity<TrackingActivityAttributes>?
    private var lastActivityState: TrackingActivityAttributes.ContentState?

    private func currentVerdict() -> (TrackingVerdict, Int) {
        if gpsQuality == .unavailable || gpsQuality == .lastKnown { return (.noGps, 0) }
        let buf = trackingEffectiveBuffer
        if buf > 0.5 { return (.ahead, max(1, Int(abs(buf).rounded()))) }
        if buf < -0.5 { return (.behind, max(1, Int(abs(buf).rounded()))) }
        return (.onTime, 0)
    }

    /// Departed once the train is `graceSec` past its EFFECTIVE (delayed)
    /// departure, matching Android's teardown. Counting the delay keeps a late
    /// train tracked instead of dropping it at the scheduled time.
    private func hasDeparted(_ focused: FocusedDeparture) -> Bool {
        focused.minutesUntil + Double(focused.delay) < -Double(PendingRouteLogic.graceSec) / 60.0
    }

    private func activityContentState(_ focused: FocusedDeparture) -> TrackingActivityAttributes.ContentState {
        let (verdict, bufMin) = currentVerdict()
        let walkMin = Int((lastWalkTime.map { $0 / 60.0 } ?? GeoUtils.walkMinutes(distanceMeters: lastWalkDist)).rounded())
        return TrackingActivityAttributes.ContentState(
            effectiveDeparture: Date(timeIntervalSince1970: TimeInterval(focused.departureTimestamp + focused.delay * 60)),
            destination: focused.destination,
            delay: focused.delay,
            platform: focused.platform,
            platformChanged: focused.platformChanged,
            verdict: verdict.rawValue,
            bufferMinutes: bufMin,
            walkMinutes: verdict == .noGps ? nil : walkMin,
            departed: hasDeparted(focused),
            schedBuf: trackingScheduledBuffer,
            effectBuf: trackingEffectiveBuffer
        )
    }

    /// `staleDate` marks when the card should dim. An immersive session refreshes
    /// every tick, so a rolling 15 min is right; a background-card session (a queued
    /// share) is never updated, so it must stay fresh until the train actually leaves
    /// — pass its effective departure. ActivityKit still enforces its own ~8 h cap,
    /// beyond which the scheduled reminder is the backstop.
    private func startLiveActivity(_ focused: FocusedDeparture, staleDate: Date? = nil) {
        endLiveActivity(departed: false) // selecting a new departure replaces the card
        // With background tracking off the session lives only as long as the
        // tracking screen, so there is nothing for a Lock Screen card to outlive.
        guard backgroundTrackingEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TrackingActivityAttributes(
            line: focused.lineNumber,
            // A queued share returns to the nearby list before starting its
            // session, so currentStation is nil here and only the background
            // session's own origin name is left.
            stationName: currentStation?.name ?? backgroundTrackedStation ?? "")
        let state = activityContentState(focused)
        lastActivityState = state
        liveActivity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate ?? Date().addingTimeInterval(900)))
    }

    private func updateLiveActivity(alertPlatformChange: Bool = false) {
        guard appState == 2, let focused = focusedTrain, let activity = liveActivity else { return }
        let state = activityContentState(focused)
        // The countdown and bar tick system-side, so only material changes
        // (or a platform alert) are worth a payload.
        guard state != lastActivityState || alertPlatformChange else { return }
        lastActivityState = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(900))
        let alert: AlertConfiguration? = alertPlatformChange
            ? AlertConfiguration(
                title: "Platform changed",
                body: "\(focused.lineNumber) \(String(localized: "Platform \(focused.platform)"))",
                sound: .default)
            : nil
        Task { await activity.update(content, alertConfiguration: alert) }
    }

    private func endLiveActivity(departed: Bool) {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        var finalState = lastActivityState
        if departed, var state = finalState {
            state.departed = true
            finalState = state
        }
        lastActivityState = nil
        Task {
            await activity.end(
                finalState.map { ActivityContent(state: $0, staleDate: nil) },
                dismissalPolicy: departed ? .after(Date().addingTimeInterval(60)) : .immediate)
        }
    }

    /// End activities orphaned by a process death mid-tracking. Called at init,
    /// when no session can legitimately exist yet.
    private func reapOrphanLiveActivities() {
        Task {
            for activity in Activity<TrackingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
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
                        status = String(localized: "No stations nearby")
                    }
                }
            } catch {
                await MainActor.run {
                    requestInFlight = false
                    requestStartTime = nil
                    handleError(error, context: String(localized: "Stations"))
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
            handleError(error, context: String(localized: "Departures"))
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
                status = String(localized: "Rate limited")
            case .httpError(let code):
                status = String(localized: "\(context): \(code)")
            case .noData:
                status = String(localized: "\(context) error")
            case .networkError:
                status = String(localized: "No connection")
            }
        } else {
            status = String(localized: "\(context) error")
        }
        departures = []
        favouriteDepartures = []
    }

    // MARK: - Watch Sending

    func refreshConnectedWatches() {
        watchService.refreshConnectedWatches()
        connectedWatches = watchService.connectedWatches
    }

    // Returns the watch's version when it is below the 0.5.x sync minimum (or no
    // version has been heard), else nil. The sync features require a watch that
    // reports 0.5.x or higher.
    private func outdatedWatchVersion(for type: PhoneWatchType) -> String? {
        let v: String?
        switch type {
        case .garmin: v = garminWatchVersion
        case .appleWatch: v = appleWatchVersion
        }
        guard !WatchSyncProtocol.meetsSyncMinimum(v) else { return nil }
        return v ?? WatchSyncProtocol.legacyVersionName
    }

    func sendToWatch(_ watch: PhoneConnectedWatch) {
        guard let focused = focusedTrain else { return }
        if let version = outdatedWatchVersion(for: watch.type) {
            watchSendStatus = String(localized: "Update TrainTime on your watch (\(version))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.watchSendStatus = nil
            }
            return
        }
        watchService.sendTrackCommand(to: watch, departure: focused, station: currentStation) { [weak self] success in
            DispatchQueue.main.async {
                self?.watchSendStatus = success ? String(localized: "Sent to \(watch.name)") : String(localized: "Failed to send")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.watchSendStatus = nil
                }
                // SDK success means "reached the device", not "the app saw it".
                // On a pv>=3 Garmin the trackStarted echo is the real ack; no echo
                // means the app was probably closed behind a stale alive reading,
                // so relaunch it with the track queued instead of leaving a false
                // "Sent".
                guard success, watch.type == .garmin, (self?.garminWatchPv ?? 0) >= 3 else { return }
                let depTs = focused.departureTimestamp
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    guard let self, self.appState == 2,
                          self.focusedTrain?.departureTimestamp == depTs,
                          !self.watchTrackingFocused else { return }
                    self.pendingWatchTrackSend = true
                    self.watchChecking = true
                    self.showWatchStatus(String(localized: "Watch app not responding, reopening..."))
                    self.watchService.openGarminApp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.watchChecking = false }
                }
            }
        }
    }

    func sendToWatch() {
        guard let watch = connectedWatches.first else {
            watchSendStatus = String(localized: "No watch connected")
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
            // Launch path: remember the intent so the hello answers with the
            // track command first, not the generic state sync.
            pendingWatchTrackSend = appState == 2 && focusedTrain != nil
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
        // A cached coordinate may be from another city; relaying it hands the
        // watch a confident-looking fix with zero proof behind it.
        guard !location.loadedFromCache else { return }
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
        guard let coord = location.coordinate, !location.loadedFromCache else { return }
        lastPushedLoc = coord
        lastLocPushTime = Date()
        mirror(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude))
    }

    // Reply to a backend's explicit reqLoc with the phone's current coordinate.
    private func replyWithLocation(to source: PhoneWatchType) {
        guard mirrorToWatch, let coord = location.coordinate, !location.loadedFromCache else { return }
        send(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude), to: source)
    }

    // Push the phone's current view onto a freshly-opened watch: the tracked train
    // or current station first — when the user is waiting on a countdown, the track
    // command must not queue behind a location push and a favourites blob — then the
    // location and favourites seeding. The peer of Android's syncCurrentStateToWatch.
    private func syncCurrentStateToWatch(to backend: PhoneWatchType) {
        sendCurrentView(to: backend)
        if mirrorToWatch, let coord = location.coordinate, !location.loadedFromCache {
            send(PhoneWatchService.GarminPayload.location(lat: coord.latitude, lon: coord.longitude), to: backend)
            lastPushedLoc = coord
            lastLocPushTime = Date()
        }
        // Re-seed favourites so a freshly-opened Garmin watch unions in any it lacks.
        if backend == .garmin {
            send(PhoneWatchService.GarminPayload.favourites(favouritesStore.favourites), to: .garmin)
        }
    }

    private func sendCurrentView(to backend: PhoneWatchType) {
        if appState == 2, let focused = focusedTrain {
            send(PhoneWatchService.GarminPayload.track(focused, station: currentStation), to: backend)
        } else if let st = currentStation, let id = st.id {
            let coord = st.coordinate
            send(PhoneWatchService.GarminPayload.station(id: id, name: st.name ?? String(localized: "Station"), lat: coord?.latitude, lon: coord?.longitude), to: backend)
        }
    }

    // The pending-track path: the tracked departure goes out first, then the
    // location/favourites seeding, then one delayed resend unless the watch's
    // trackStarted echo already confirmed it landed (a send can race the watch's
    // cold start and vanish — the silent "it just didn't track" failure).
    private func sendFocusedTrackFirst(to backend: PhoneWatchType) {
        guard appState == 2, let focused = focusedTrain else {
            syncCurrentStateToWatch(to: backend)
            return
        }
        let payload = PhoneWatchService.GarminPayload.track(focused, station: currentStation)
        send(payload, to: backend)
        pushLocationNow()
        if backend == .garmin {
            send(PhoneWatchService.GarminPayload.favourites(favouritesStore.favourites), to: .garmin)
        }
        let depTs = focused.departureTimestamp
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.appState == 2,
                  self.focusedTrain?.departureTimestamp == depTs,
                  !self.watchTrackingFocused else { return }
            self.send(payload, to: backend)
        }
    }

    // Tap on the watch indicator / "Open on watch" button. Garmin can be launched remotely;
    // Apple Watch cannot (no API), so it re-syncs when reachable or guides the user otherwise.
    func openWatchApp() {
        switch resolvedPrimaryWatch {
        case .garmin:
            refreshConnectedWatches()
            if !watchService.hasGarminWatch {
                showWatchStatus(String(localized: "No watch connected"))
                return
            }
            if garminAlive {
                if pendingWatchTrackSend {
                    pendingWatchTrackSend = false
                    sendFocusedTrackFirst(to: .garmin)
                } else {
                    syncCurrentStateToWatch(to: .garmin)
                }
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
                if pendingWatchTrackSend {
                    pendingWatchTrackSend = false
                    sendFocusedTrackFirst(to: .appleWatch)
                } else {
                    syncCurrentStateToWatch(to: .appleWatch)
                }
            } else {
                showWatchStatus(String(localized: "Open TrainTime on your watch"))
            }
        case .none:
            showWatchStatus(String(localized: "No watch connected"))
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

        // traintime://resumeroute, reminder notification tap. Track the current
        // leg directly (no prompt); the chip covers the manual case.
        if url.host == "resumeroute" {
            if appState == 3 { resumeFromInactive() }
            resumePendingRoute()
            return
        }

        // traintime://sendtowatch, reminder "Send to Watch" action. The app is now
        // foreground (Connect IQ only binds there), so push the route to Garmin.
        if url.host == "sendtowatch" {
            if appState == 3 { resumeFromInactive() }
            sendPendingRouteToWatch()
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
            shareStatus = String(localized: "No SBB trip link found")
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
                case .unsupportedVersion: shareStatus = String(localized: "This SBB link format isn't supported yet")
                case .noRideLegs: shareStatus = String(localized: "Nothing to track in this trip")
                case .malformed: shareStatus = String(localized: "Couldn't read this trip link")
                }
            } catch {
                shareStatus = String(localized: "Couldn't open the link. Check your connection")
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
        proceedOffer(offer)
    }

    /// A board save queues straight away; an SBB share consults the live board.
    private func proceedOffer(_ offer: SharedRouteOffer) {
        if offer.saveOnly { saveOfferAsQueued(offer) } else { proceedWithSharedRoute(offer) }
    }

    func confirmReplaceSharedRoute() {
        guard let offer = shareReplaceOffer else { return }
        shareReplaceOffer = nil
        proceedOffer(offer)
    }

    func dismissReplaceSharedRoute() {
        shareReplaceOffer = nil
    }

    /// Bypass the nearby flow: show the leg's origin as the sole station and
    /// fetch its board; the fetch completion decides track-now vs save-for-later.
    private func proceedWithSharedRoute(_ offer: SharedRouteOffer) {
        let now = Int(Date().timeIntervalSince1970)
        guard let index = offer.route.targetRideLegIndex(now: now) else {
            shareStatus = String(localized: "This trip is already underway or finished")
            return
        }
        let leg = offer.route.legs[index]
        guard let stationId = leg.originId else {
            shareStatus = String(localized: "Couldn't read this trip link")
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
            id: id, name: name ?? String(localized: "Station"), lat: lat, lon: lon,
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
            selectDepartureImpl(match, routeDestination: pending.finalDestination)
        } else if leg.isTrackable, forced != nil || PendingRouteLogic.isResumable(pending, now: now) {
            // Not on the board yet, but the user explicitly opened it (forced),
            // or it's close enough to resume: open a local countdown that
            // survives until the train departs. Never wall the user out.
            var tracking = pending
            tracking.status = PendingRoute.statusTracking
            pendingRouteStore.save(tracking)
            PendingRouteNotifier.schedule(pending, now: now)
            enterProtectedTrack(leg, routeDestination: pending.finalDestination)
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
        // Pin the reminder's walk time to where the user actually is now, not the
        // last nearby-search coordinate, so the distance-aware lead matches the
        // live walk shown on the board.
        location.saveLastKnownCoordinate()
        PendingRouteNotifier.schedule(pending, now: now)
        syncReminderTracking()
        shareStatus = String(localized: "Saved. We'll remind you before departure")
        // Don't strand the user on the remote origin board. Return to their real
        // location, then start a live background session for the queued leg so the
        // countdown card + Live Activity appear (paused while far, ramping near
        // departure). The reminder above stays as the reboot backstop.
        returnToNearbyIfLaunched()
        if index >= 0, index < pending.legs.count {
            let leg = pending.legs[index]
            enterBackgroundTrack(leg, station: leg.originName, routeDestination: pending.finalDestination)
        }
    }

    /// Save a single board departure as a pending route, so it rides the same
    /// distance-aware reminder as an SBB share. Tapping a row tracks now; this
    /// explicitly saves for later, which matters most for a far-future departure.
    /// Peer of MainViewModel.saveDepartureAsPending.
    func saveDepartureAsPending(_ departure: Departure) {
        lastInteractionTime = Date()
        guard let station = currentStation, departure.departureTimestamp != nil else {
            shareStatus = String(localized: "Couldn't save this departure")
            return
        }
        saveRouteOffer(SharedRoute.forDeparture(station: station, departure: departure))
    }

    /// Save an externally-built one-leg route (the watch's remind-on-phone command).
    func saveExternalRouteAsPending(_ route: SharedRoute) {
        saveRouteOffer(route)
    }

    /// A live session that keeps running in the background (the Live Activity)
    /// while the board is shown. Non-nil = "Track in the background" is active:
    /// the board pins it at the top, tapping it re-opens full tracking. Peer of
    /// MainViewModel.backgroundTracked.
    @Published var backgroundTracked: FocusedDeparture?
    @Published var backgroundTrackedStation: String?

    /// Tracking-screen "Track in the background": leave the immersive tracking
    /// screen for the board but keep the Live Activity running. No reminder, no
    /// disclosure prompt — the Live Activity already covers the closed-app case.
    func trackCurrentInBackground() {
        lastInteractionTime = Date()
        guard backgroundTrackingEnabled else { return }
        guard let focused = focusedTrain else { return }
        backgroundTracked = focused
        backgroundTrackedStation = currentStation?.name
        // Exit to the board WITHOUT ending the Live Activity (unlike exit): it
        // keeps counting down system-side.
        appState = 0
        location.setTrackingAccuracy(false)
        lastLocationTier = nil
        focusedTrain = nil
        formation = nil
        consecutiveErrors = 0
        scheduleApproachAlertIfEnabled(for: focused)
        startTimer(interval: Timing.normalRefreshInterval)
        returnToNearbyIfLaunched()
    }

    /// The board-card session's one-shot "time to leave" alert. Skipped when a
    /// saved route already owns the reminder (it survives reboot too) or the user
    /// turned it off. Distance-aware lead comes from the live walk we last had.
    private func scheduleApproachAlertIfEnabled(for focused: FocusedDeparture) {
        guard UserDefaults.standard.object(forKey: "alertBeforeDeparture") as? Bool ?? true,
              pendingRouteStore.pending == nil else { return }
        let distanceAware = UserDefaults.standard.bool(forKey: "distanceAwareReminder")
        let walkSec = distanceAware
            ? (lastWalkTime.map { Int($0) } ?? Int(GeoUtils.walkMinutes(distanceMeters: lastWalkDist) * 60))
            : 0
        PendingRouteNotifier.scheduleApproachAlert(focused, walkSeconds: walkSec, now: Int(Date().timeIntervalSince1970))
    }

    /// Board "now tracking" card tapped: re-open the full tracking screen for the
    /// session running in the background.
    func resumeBackgroundTracking() {
        guard let dep = backgroundTracked else { return }
        backgroundTracked = nil
        backgroundTrackedStation = nil
        PendingRouteNotifier.cancelApproachAlert()
        beginTracking(dep)
    }

    /// Board "now tracking" card stop: end the background session and its
    /// Live Activity without re-opening the tracking screen. When a shared route
    /// backs the session, X clears the whole journey (route + reminder), matching
    /// the old chip's discard — the card is now the single surface for it.
    func stopBackgroundTracking() {
        let wasRoute = pendingRouteStore.pending != nil
        backgroundTracked = nil
        backgroundTrackedStation = nil
        PendingRouteNotifier.cancelApproachAlert()
        endLiveActivity(departed: false)
        if wasRoute { dismissPendingRoute() }
    }

    /// Start a live background session for a leg the user hasn't opened
    /// immersively — a shared route queued far out. The Live Activity carries the
    /// countdown (paused tier: no polling, no GPS while far), the board shows the
    /// now-tracking card, and the pending route + reminder stay as the reboot
    /// backstop. No-op if a session is already running.
    private func enterBackgroundTrack(_ leg: RouteLeg, station: String?, routeDestination: String?) {
        guard backgroundTrackingEnabled else { return }
        guard backgroundTracked == nil, appState != 2, leg.isTrackable else { return }
        let focused = FocusedDeparture(
            destination: leg.destName,
            departureTimestamp: leg.depTs,
            lineNumber: leg.lineNumber ?? "",
            category: leg.category ?? "",
            trainNumber: leg.trainNumber,
            operatorRef: nil,
            delay: 0,
            platform: "",
            platformChanged: false,
            routeDestination: routeDestination
        )
        backgroundTracked = focused
        backgroundTrackedStation = station
        // A queued share is never updated (updateLiveActivity is immersive-only), so
        // keep the card fresh until the train's effective departure rather than the
        // default 15 min — a share hours out must not dim minutes after it appears.
        let effectiveDep = Date(timeIntervalSince1970: TimeInterval(focused.departureTimestamp + focused.delay * 60))
        startLiveActivity(focused, staleDate: effectiveDep)
    }

    private func saveRouteOffer(_ route: SharedRoute) {
        let offer = SharedRouteOffer(route: route, sourceUrl: nil, saveOnly: true)
        Task { await openSharedRoute(offer) }
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
            shareStatus = String(localized: "Saved route to \(current.finalDestination) has passed")
            return
        }
        if normalized != current {
            pendingRouteStore.save(normalized)
            PendingRouteNotifier.schedule(normalized, now: now)
        }
    }

    /// Notification tap / route-view "Track now" on the current leg. An explicit
    /// resume always opens the countdown, even hours out. A live board match gives
    /// real delay/platform, otherwise a local countdown. Never re-queues.
    func resumePendingRoute() {
        guard let route = pendingRouteStore.pending else { return }
        let now = Int(Date().timeIntervalSince1970)
        guard let normalized = PendingRouteLogic.normalize(route, now: now) else {
            Task { @MainActor in await refreshPendingRoute() }
            return
        }
        trackLegImpl(normalized, index: normalized.cursor)
    }

    /// Reminder "Send to Watch" action (traintime://sendtowatch). The app is now
    /// foreground, so Connect IQ is bound. Build the current leg's track, wake the
    /// Garmin app, and transmit over a short window (silent drop if it never wakes),
    /// matching the Android path.
    func sendPendingRouteToWatch() {
        let now = Int(Date().timeIntervalSince1970)
        guard let route = pendingRouteStore.pending.flatMap({ PendingRouteLogic.normalize($0, now: now) }),
              let leg = route.currentLeg else { return }
        watchService.initialize()
        watchService.refreshConnectedWatches()
        guard watchService.hasGarminWatch else {
            watchSendStatus = String(localized: "No watch connected")
            return
        }
        let payload = PhoneWatchService.GarminPayload.track(leg: leg, finalDestination: route.finalDestination)
        // Wake the watch app, then send on its hello (garminAlive flips true) rather
        // than a blind timer: a track sent before the watch registers for phone
        // messages is dropped. Fall back to a bounded blind send if no hello arrives
        // (never regress), then reopen so the now-tracking app pulls to the front — a
        // launch issued from the watch's notification view often doesn't foreground it
        // (a Garmin OS call). Mirrors Android's wait-for-alive path.
        watchService.openGarminApp()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline && !self.garminAlive {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            self.watchService.sendToGarminWatches(payload)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.watchService.sendToGarminWatches(payload)
            self.watchSendStatus = String(localized: "Sent to watch")
            self.watchService.openGarminApp()
        }
    }

    /// Route-view "Track now" on any trackable leg (may jump ahead to a later
    /// connection). Untrackable legs (walk / outside Switzerland) are ignored.
    func trackLeg(_ index: Int) {
        guard let route = pendingRouteStore.pending else { return }
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
        enterProtectedTrack(leg, routeDestination: route.finalDestination)
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

    /// While tracking a shared-route leg, every remaining ride leg of the same
    /// route: the onward journey, each shown as its own card under the countdown
    /// and tappable to jump onto it early. Change minutes measure from the
    /// previous ride leg's arrival. Empty for a plain (non-route) track.
    var onwardLegs: [OnwardConnection] {
        guard let focused = focusedTrain, let route = pendingRouteStore.pending else { return [] }
        guard let curIdx = route.legs.firstIndex(where: {
            $0.type == .ride && $0.depTs == focused.departureTimestamp
        }) else { return [] }
        var result: [OnwardConnection] = []
        var prevRide = route.legs[curIdx]
        var i = curIdx + 1
        while i < route.legs.count {
            let leg = route.legs[i]
            if leg.type == .ride {
                let changeMinutes = max(0, (leg.depTs - prevRide.arrTs) / 60)
                result.append(OnwardConnection(changeStation: prevRide.destName, leg: leg, legIndex: i, changeMinutes: changeMinutes))
                prevRide = leg
            }
            i += 1
        }
        return result
    }

    /// The immediate next connection, for surfaces that show only one.
    var onwardConnection: OnwardConnection? { onwardLegs.first }

    func dismissPendingRoute() {
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
    /// A board "Remind me" save always queues for a reminder, never tracks now
    /// (tapping the row already tracks). SBB shares leave this false and decide
    /// track-vs-queue from the live board.
    var saveOnly: Bool = false

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
