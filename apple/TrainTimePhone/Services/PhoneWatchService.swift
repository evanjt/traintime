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
    let wcService = WatchConnectivityService()
    let garminService = GarminConnectIQService()

    @Published var connectedWatches: [PhoneConnectedWatch] = []

    func initialize() {
        garminService.initialize()
    }

    func shutdown() {
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
    }

    /// Connect IQ phone-app payloads for the action-dispatched Garmin contract the
    /// watch reads in handlePhoneMessage (track / mode / station / loc). One source
    /// of truth, mirroring WearSync.garmin*Payload on Android.
    enum GarminPayload {
        static func track(_ departure: FocusedDeparture, stationId: String?) -> [String: Any] {
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
            if let stId = stationId { data["stId"] = stId }
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
        stationId: String?,
        completion: @escaping (Bool) -> Void
    ) {
        let data = GarminPayload.track(departure, stationId: stationId)

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
