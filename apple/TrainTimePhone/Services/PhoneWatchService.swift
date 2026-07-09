import Foundation

enum PhoneWatchType: Equatable {
    case appleWatch
    case garmin
}

/// Which watch backend the phone drives when more than one is paired. Persisted as the
/// raw string under "primaryWatch". `auto` resolves to the only known backend, or Apple
/// Watch when both are present.
enum PrimaryWatchPreference: String {
    case auto
    case appleWatch
    case garmin
}

/// Three-state liveness used by the header + tracking indicators, unified across both
/// backends: green = open and synced, amber = connected/recent but app closed, grey =
/// paired but unreachable, hidden = no watch known.
enum WatchLiveness: Equatable {
    case green
    case amber
    case grey
    case hidden
}

struct PhoneConnectedWatch: Identifiable {
    let id: String
    let name: String
    let type: PhoneWatchType
}

class PhoneWatchService: ObservableObject {
    /// One Connect IQ registration per process, shared by the ViewModel and the
    /// AppDelegate's background "Send to Watch" notification-action handler (which
    /// runs with no ViewModel alive).
    static let shared = PhoneWatchService()

    let wcService = WatchConnectivityService()
    let garminService = GarminConnectIQService()

    @Published var connectedWatches: [PhoneConnectedWatch] = []

    private var initialised = false

    func initialize() {
        guard !initialised else { return }
        initialised = true
        garminService.initialize()
    }

    func shutdown() {
        initialised = false
        garminService.shutdown()
    }

    func refreshConnectedWatches() {
        var watches: [PhoneConnectedWatch] = []

        // Apple Watch via WatchConnectivity
        if wcService.isPaired {
            watches.append(PhoneConnectedWatch(
                id: "applewatch",
                name: "Apple Watch",
                type: .appleWatch
            ))
        }

        // Garmin via Connect IQ
        let garminDevices = garminService.getConnectedDevices()
        for device in garminDevices {
            watches.append(PhoneConnectedWatch(
                id: "garmin_\(device.id)",
                name: device.name,
                type: .garmin
            ))
        }

        connectedWatches = watches

        // Latch "a Garmin has actually connected here" for the reminder scheduler
        // (schedule/notify runs with no live SDK). Sticky and set only from a live
        // connection, so the "Send to Watch" action never appears for someone who
        // has never connected a Garmin. The handler re-checks liveness before sending.
        if hasGarminWatch {
            UserDefaults.standard.set(true, forKey: "garminEverConnected")
        }
    }

    /// Connect IQ phone-app payloads for the action-dispatched Garmin contract the
    /// watch reads in handlePhoneMessage (track / mode / station / loc). One source
    /// of truth, mirroring WearSync.garmin*Payload on Android.
    enum GarminPayload {
        static func track(_ departure: FocusedDeparture, station: Station?) -> [String: Any] {
            var data: [String: Any] = [
                "action": "track",
                "dest": departure.destination,
                "depTs": departure.departureTimestamp,
                "delay": departure.delay,
                "plat": departure.platform,
                "platChg": departure.platformChanged,
                "cat": departure.category,
                "line": departure.lineNumber
            ]
            if let tn = departure.trainNumber { data["trainNum"] = tn }
            if let op = departure.operatorRef { data["opRef"] = op }
            // Station identity and coordinate so the watch can poll the board
            // and compute walk distance. Garmin ignores the extra keys.
            if let station, let stId = station.id {
                data["stId"] = stId
                if let name = station.name { data["stName"] = name }
                if let lat = station.lat { data["stLat"] = lat }
                if let lon = station.lon { data["stLon"] = lon }
            }
            return data
        }

        /// Track payload sourced from a saved-route leg (Send to Watch from the
        /// reminder), rather than a live board row. Same contract as
        /// track(_:station:); `dest` is the route's final destination, the leg
        /// origin drives the watch's board poll + walk distance.
        static func track(leg: RouteLeg, finalDestination: String) -> [String: Any] {
            var data: [String: Any] = [
                "action": "track",
                "dest": finalDestination,
                "depTs": leg.depTs,
                "delay": 0,
                "plat": "",
                "platChg": false,
                "cat": leg.category ?? "",
                "line": leg.lineNumber ?? ""
            ]
            if let tn = leg.trainNumber { data["trainNum"] = tn }
            if let stId = leg.originId {
                data["stId"] = stId
                data["stName"] = leg.originName
                if let lat = leg.originLat { data["stLat"] = lat }
                if let lon = leg.originLon { data["stLon"] = lon }
            }
            return data
        }

        static func mode(_ mode: Int) -> [String: Any] {
            ["action": "mode", "mode": mode]
        }

        static func station(id: String, name: String, lat: Double?, lon: Double?) -> [String: Any] {
            var data: [String: Any] = ["action": "station", "stId": id, "name": name]
            if let lat { data["lat"] = lat }
            if let lon { data["lon"] = lon }
            return data
        }

        static func location(lat: Double, lon: Double) -> [String: Any] {
            ["action": "loc", "lat": lat, "lon": lon]
        }

        // Receipt ack for a watch-queued reminder. The watch keeps the reminder
        // in its outbox and retries until it sees this id come back.
        static func ackReminder(id: String) -> [String: Any] {
            ["action": "ackReminder", "id": id]
        }

        // Foreground liveness probe; the watch answers with an immediate hello.
        // Only sent through the WatchSyncProtocol.shouldPingGarmin gate.
        static func ping() -> [String: Any] {
            ["action": "ping"]
        }

        // The phone's favourites for the Garmin outer-join sync. The watch unions
        // these into its own store (never replaces).
        static func favourites(_ favourites: [Favourite]) -> [String: Any] {
            ["action": "favourites",
             "favs": favourites.map {
                 ["stId": $0.stationId, "name": $0.stationName, "line": $0.lineNumber, "dest": $0.destination]
             }]
        }
    }

    /// True when a Garmin watch is currently reachable, so the phone can mirror to it.
    var hasGarminWatch: Bool { !garminService.getConnectedDevices().isEmpty }

    /// A Garmin watch is paired (possibly off / out of range), drives the grey indicator
    /// and primary-watch resolution.
    var hasKnownGarmin: Bool { garminService.hasKnownDevices }

    /// An Apple Watch is paired with TrainTime installed (possibly with the app closed).
    var hasKnownAppleWatch: Bool { wcService.isPaired && wcService.isWatchAppInstalled }

    /// Push a raw action payload to every connected Garmin watch (state mirroring +
    /// location backfill). Fire-and-forget; no watch → no-op.
    func sendToGarminWatches(_ data: [String: Any]) {
        for device in garminService.getConnectedDevices() {
            garminService.sendMessage(to: device, data: data) { _ in }
        }
    }

    /// Open TrainTime on the connected Garmin watch(es). No Apple Watch equivalent exists.
    func openGarminApp() {
        for device in garminService.getConnectedDevices() {
            garminService.openApplication(on: device)
        }
    }

    /// Mirror an action payload to the Apple Watch (live only when reachable). The peer of
    /// sendToGarminWatches for the WCSession backend.
    func sendToAppleWatch(_ data: [String: Any]) {
        wcService.mirror(data)
    }

    func sendTrackCommand(
        to watch: PhoneConnectedWatch,
        departure: FocusedDeparture,
        station: Station?,
        completion: @escaping (Bool) -> Void
    ) {
        let data = GarminPayload.track(departure, station: station)

        switch watch.type {
        case .appleWatch:
            wcService.sendMessage(data, completion: completion)
        case .garmin:
            let garminDevices = garminService.getConnectedDevices()
            // watch.id is "garmin_<deviceId>"; match on the stable identifier.
            let wantedId = String(watch.id.dropFirst("garmin_".count))
            if let device = garminDevices.first(where: { $0.id == wantedId }) {
                garminService.sendMessage(to: device, data: data, completion: completion)
            } else {
                completion(false)
            }
        }
    }
}
