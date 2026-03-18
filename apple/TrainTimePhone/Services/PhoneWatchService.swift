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
        for (i, device) in garminDevices.enumerated() {
            watches.append(PhoneConnectedWatch(
                id: "garmin_\(i)",
                name: device.name,
                type: .garmin
            ))
        }

        connectedWatches = watches
    }

    func sendTrackCommand(
        to watch: PhoneConnectedWatch,
        departure: FocusedDeparture,
        stationId: String?,
        completion: @escaping (Bool) -> Void
    ) {
        var data: [String: Any] = [
            "action": "track",
            "dest": departure.destination,
            "depTs": departure.departureTimestamp,
            "delay": departure.delay,
            "plat": departure.platform,
            "platChg": departure.platformChanged,
            "cat": departure.category
        ]
        if let tn = departure.trainNumber {
            data["trainNum"] = tn
        }
        if let stId = stationId {
            data["stId"] = stId
        }

        switch watch.type {
        case .appleWatch:
            wcService.sendMessage(data, completion: completion)
        case .garmin:
            let garminDevices = garminService.getConnectedDevices()
            // Find matching device by name
            if let device = garminDevices.first(where: { $0.name == watch.name }) {
                garminService.sendMessage(to: device, data: data, completion: completion)
            } else {
                completion(false)
            }
        }
    }
}
