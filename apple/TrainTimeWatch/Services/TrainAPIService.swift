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
    private static let apiKey = Secrets.apiKey

    // MARK: - Station Search by Coordinates

    static func fetchStations(
        lat: Double, lon: Double, mode: TransportMode? = nil
    ) async throws -> (train: [Station], bus: [Station], tram: [Station], special: [Station]) {
        var urlString = "\(baseURL)/v1/nearby?lat=\(lat)&lon=\(lon)"
        if let mode = mode {
            switch mode {
            case .bus: urlString += "&mode=bus"
            case .tram: urlString += "&mode=tram"
            case .special: urlString += "&mode=special"
            default: break
            }
        }
        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let trainStations = parseStationGroup(json["train"], mode: .train)
        let busStations = parseStationGroup(json["bus"], mode: .bus)
        let tramStations = parseStationGroup(json["tram"], mode: .tram)
        let specialStations = parseStationGroup(json["special"], mode: .special)

        return (trainStations, busStations, tramStations, specialStations)
    }

    // MARK: - Departures

    static func fetchDepartures(stationId: String, favourites: String? = nil) async throws -> (departures: [Departure], favourites: [Departure]) {
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        var urlString = "\(baseURL)/v1/departures?id=\(encoded)&limit=\(Thresholds.maxDepartures)"
        if let favParam = favourites?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&favourites=\(favParam)"
        }
        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await makeRequest(url: url)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let departureArray = json?["departures"] as? [[String: Any]] else {
            return ([], [])
        }

        let deps = departureArray.prefix(Thresholds.maxDepartures).map { Departure.from(json: $0) }
        let favDeps: [Departure]
        if let favArray = json?["favourites"] as? [[String: Any]] {
            favDeps = favArray.map { Departure.from(json: $0) }
        } else {
            favDeps = []
        }
        return (Array(deps), favDeps)
    }

    // MARK: - Formation

    static func fetchFormation(trainNumber: String, date: String, stationId: String, operatorRef: String? = nil) async throws -> Formation? {
        let encodedStation = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        var urlString = "\(baseURL)/v1/formation?train=\(trainNumber)&date=\(date)&stop=\(encodedStation)"
        if let op = operatorRef {
            urlString += "&operatorRef=\(op)"
        }
        guard let url = URL(string: urlString) else { return nil }

        let (data, response) = try await makeRequest(url: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return Formation.from(json: json)
    }

    // MARK: - Helpers

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
