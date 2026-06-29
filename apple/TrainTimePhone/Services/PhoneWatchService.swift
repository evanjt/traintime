import Foundation

enum PhoneWatchType {
    case appleWatch
    case garmin
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

    /// Push a raw action payload to every connected Garmin watch (state mirroring +
    /// location backfill). Fire-and-forget; no watch → no-op.
    func sendToGarminWatches(_ data: [String: Any]) {
        for device in garminService.getConnectedDevices() {
            garminService.sendMessage(to: device, data: data) { _ in }
        }
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
