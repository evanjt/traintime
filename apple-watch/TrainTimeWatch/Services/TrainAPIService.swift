import Foundation
import CoreLocation

enum TrainAPIError: Error {
    case rateLimited
    case httpError(Int)
    case noData
    case networkError
}

struct TrainAPIService {
    private static let baseURL = "https://transport.opendata.ch/v1"

    // MARK: - Station Search by Coordinates

    /// Two-phase station discovery: coordinate search, then name fallback for trains
    static func fetchStations(
        lat: Double, lon: Double
    ) async throws -> (train: [Station], bus: [Station], tram: [Station], special: [Station]) {
        let userCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        // Phase 1: coordinate search
        let urlString = "\(baseURL)/locations?x=\(lat)&y=\(lon)&type=station"
        let allStations = try await fetchStationList(urlString: urlString, userCoord: userCoord)

        var trainStations: [Station] = []
        var busStations: [Station] = []
        var tramStations: [Station] = []

        for station in allStations {
            switch station.mode {
            case .train:
                if trainStations.count < Thresholds.maxStationsPerMode {
                    trainStations.append(station)
                }
            case .bus:
                if busStations.count < Thresholds.maxStationsPerMode {
                    busStations.append(station)
                }
            case .tram:
                if tramStations.count < Thresholds.maxStationsPerMode {
                    tramStations.append(station)
                }
            case .special:
                break
            }
        }

        // Phase 2: name fallback if no train stations found
        if trainStations.isEmpty, let firstBus = (busStations.first ?? tramStations.first) {
            if let cityName = extractCityName(from: firstBus.name) {
                let fallbackTrains = try await fetchTrainStationsByName(
                    city: cityName, userCoord: userCoord
                )
                trainStations = fallbackTrains
            }
        }

        return (trainStations, busStations, tramStations, [])
    }

    // MARK: - Station Search by Name (Fallback)

    private static func fetchTrainStationsByName(
        city: String, userCoord: CLLocationCoordinate2D
    ) async throws -> [Station] {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlString = "\(baseURL)/locations?query=\(encoded)&type=station"
        let stations = try await fetchStationList(urlString: urlString, userCoord: userCoord)

        return stations.filter { station in
            // Exclude bus and tram
            guard station.mode == .train else { return false }
            // Must be within 5km
            guard let coord = station.coordinate else { return false }
            let dist = GeoUtils.haversineDistance(from: userCoord, to: coord)
            return dist <= Thresholds.fallbackSearchRadius
        }.prefix(Thresholds.maxStationsPerMode).map { $0 }
    }

    // MARK: - Shared Station Fetch

    private static func fetchStationList(
        urlString: String, userCoord: CLLocationCoordinate2D?
    ) async throws -> [Station] {
        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let stationArray = json?["stations"] as? [[String: Any]] else {
            return []
        }

        return stationArray.compactMap { Station.from(json: $0, userCoord: userCoord) }
    }

    // MARK: - Departures

    static func fetchDepartures(stationId: String) async throws -> [Departure] {
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        let urlString = "\(baseURL)/stationboard"
            + "?id=\(encoded)"
            + "&limit=\(Thresholds.maxDepartures)"
            + "&fields[]=stationboard/to"
            + "&fields[]=stationboard/category"
            + "&fields[]=stationboard/number"
            + "&fields[]=stationboard/stop/departureTimestamp"
            + "&fields[]=stationboard/stop/delay"
            + "&fields[]=stationboard/stop/platform"
            + "&fields[]=stationboard/stop/prognosis/platform"

        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let stationboard = json?["stationboard"] as? [[String: Any]] else {
            return []
        }

        let now = Int(Date().timeIntervalSince1970)
        var departures: [Departure] = []

        for entry in stationboard.prefix(Thresholds.maxDepartures) {
            let destination = entry["to"] as? String ?? "?"
            let category = entry["category"] as? String ?? ""
            let number = entry["number"] as? String ?? ""
            let lineNumber = (category == "B" || category == "T" || category == "NFB" || category == "NFT" || category == "M") ? number : ""
            let stop = entry["stop"] as? [String: Any] ?? [:]

            // Platform logic: prognosis overrides scheduled
            var platform = ""
            var platformChanged = false
            let prognosis = stop["prognosis"] as? [String: Any]
            let progPlatform = prognosis?["platform"] as? String
            let schedPlatform: String? = {
                if let s = stop["platform"] as? String { return s }
                if let n = stop["platform"] as? Int { return String(n) }
                return nil
            }()

            if let prog = progPlatform {
                platform = prog
                if let sched = schedPlatform, sched != prog {
                    platformChanged = true
                }
            } else if let sched = schedPlatform {
                platform = sched
            }

            // Departure timestamp and minutes
            var minutesUntil = -1
            var depTimestamp: Int?
            if let depTs = stop["departureTimestamp"] as? Int {
                depTimestamp = depTs
                minutesUntil = (depTs - now) / 60
            }

            // Delay
            var delay = 0
            if let rawDelay = stop["delay"] as? Int, rawDelay > 0 {
                delay = rawDelay
            }

            departures.append(Departure(
                destination: destination,
                minutesUntil: minutesUntil,
                departureTimestamp: depTimestamp,
                delay: delay,
                platform: platform,
                platformChanged: platformChanged,
                lineNumber: lineNumber
            ))
        }

        return departures
    }

    // MARK: - Helpers

    /// Extract city name from station name (e.g., "Sion, Place du Midi" → "Sion")
    static func extractCityName(from name: String?) -> String? {
        guard let name = name else { return nil }
        if let commaIndex = name.firstIndex(of: ",") {
            let city = String(name[name.startIndex..<commaIndex]).trimmingCharacters(in: .whitespaces)
            return city.isEmpty ? nil : city
        }
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
    }

    private static func makeRequest(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(from: url)
        } catch {
            throw TrainAPIError.networkError
        }
    }

    private static func checkHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 { throw TrainAPIError.rateLimited }
        if http.statusCode != 200 { throw TrainAPIError.httpError(http.statusCode) }
    }
}
