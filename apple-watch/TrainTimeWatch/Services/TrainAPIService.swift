import Foundation
import CoreLocation

enum TrainAPIError: Error {
    case rateLimited
    case httpError(Int)
    case noData
    case networkError
}

struct TrainAPIService {
    private static let baseURL = "https://api.traintime.ch"
    private static let apiKey = "***REDACTED***"

    // MARK: - Station Search by Coordinates

    static func fetchStations(
        lat: Double, lon: Double
    ) async throws -> (train: [Station], bus: [Station], tram: [Station], special: [Station]) {
        let urlString = "\(baseURL)/v1/nearby?lat=\(lat)&lon=\(lon)"
        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let trainStations = parseStationGroup(json["train"], mode: .train)
        let busStations = parseStationGroup(json["bus"], mode: .bus)
        let tramStations = parseStationGroup(json["tram"], mode: .tram)
        let specialStations = parseStationGroup(json["special"], mode: .special)

        // Name fallback: if no train stations, search by city name
        if trainStations.isEmpty, let firstBus = (busStations.first ?? tramStations.first) {
            if let cityName = extractCityName(from: firstBus.name) {
                let fallbackTrains = try await fetchTrainStationsByName(
                    city: cityName, lat: lat, lon: lon
                )
                return (fallbackTrains, busStations, tramStations, specialStations)
            }
        }

        return (trainStations, busStations, tramStations, specialStations)
    }

    // MARK: - Station Search by Name (Fallback)

    private static func fetchTrainStationsByName(
        city: String, lat: Double, lon: Double
    ) async throws -> [Station] {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlString = "\(baseURL)/v1/nearby?lat=\(lat)&lon=\(lon)&query=\(encoded)"
        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return parseStationGroup(json["train"], mode: .train)
    }

    // MARK: - Departures

    static func fetchDepartures(stationId: String) async throws -> [Departure] {
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        let urlString = "\(baseURL)/v1/departures?id=\(encoded)&limit=\(Thresholds.maxDepartures)"
        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let departureArray = json?["departures"] as? [[String: Any]] else {
            return []
        }

        let now = Int(Date().timeIntervalSince1970)
        var departures: [Departure] = []

        for entry in departureArray.prefix(Thresholds.maxDepartures) {
            let destination = entry["to"] as? String ?? "?"
            let category = entry["category"] as? String ?? ""
            let number = entry["number"] as? String ?? ""
            let lineNumber = (category == "B" || category == "T" || category == "NFB" || category == "NFT" || category == "M") ? number : ""

            let platform = entry["platform"] as? String ?? ""
            let platformChanged = entry["platformChanged"] as? Bool ?? false

            var minutesUntil = -1
            var depTimestamp: Int?
            if let depTs = entry["departure"] as? Int {
                depTimestamp = depTs
                minutesUntil = (depTs - now) / 60
            }

            var delay = 0
            if let rawDelay = entry["delay"] as? Int, rawDelay > 0 {
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

    private static func parseStationGroup(_ raw: Any?, mode: TransportMode) -> [Station] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { Station.from(json: $0, mode: mode) }
    }

    private static func makeRequest(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        do {
            return try await URLSession.shared.data(for: request)
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
