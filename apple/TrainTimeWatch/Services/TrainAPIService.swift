import Foundation
import CoreLocation

enum TrainAPIError: Error {
    case rateLimited
    case updateRequired
    /// The timetable source behind every host is down; no other host helps.
    case upstreamUnavailable
    case httpError(Int)
    case noData
    case networkError
}

struct TrainAPIService {
    private static let apiKey = Secrets.apiKey

    // MARK: - Station Search by Coordinates

    static func fetchStations(
        lat: Double, lon: Double, mode: TransportMode? = nil
    ) async throws -> (train: [Station], bus: [Station], tram: [Station], special: [Station]) {
        var path = "/v1/nearby?lat=\(lat)&lon=\(lon)"
        if let mode = mode {
            switch mode {
            case .bus: path += "&mode=bus"
            case .tram: path += "&mode=tram"
            case .special: path += "&mode=special"
            default: break
            }
        }

        let (data, response) = try await makeRequest(path: path)
        try checkHTTPResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let trainStations = parseStationGroup(json["train"], mode: .train)
        let busStations = parseStationGroup(json["bus"], mode: .bus)
        let tramStations = parseStationGroup(json["tram"], mode: .tram)
        let specialStations = parseStationGroup(json["special"], mode: .special)

        return (trainStations, busStations, tramStations, specialStations)
    }

    // MARK: - Departures

    /// The departures a station's board shows. `staleSince` is the unix time
    /// the list was fetched when the API served it through an upstream outage,
    /// nil for a live list.
    typealias DeparturesBoard = (departures: [Departure], favourites: [Departure], staleSince: Int?)

    /// `showsAge` opts in to a list served through an upstream outage past the
    /// short window. Only a caller that shows `staleSince` passes it: elsewhere
    /// that list would read as live.
    static func fetchDepartures(stationId: String, favourites: String? = nil, showsAge: Bool = false) async throws -> DeparturesBoard {
        let path = departuresPath(stationId: stationId, favourites: favourites, showsAge: showsAge)
        let (data, response) = try await makeRequest(path: path)
        try checkHTTPResponse(response, data: data)
        return try parseDepartures(data)
    }

    static func departuresPath(stationId: String, favourites: String?, showsAge: Bool) -> String {
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        var path = "/v1/departures?id=\(encoded)&limit=\(Thresholds.maxDepartures)"
        if let favParam = favourites?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&favourites=\(favParam)"
        }
        if showsAge {
            path += "&stale=1"
        }
        return path
    }

    static func parseDepartures(_ data: Data) throws -> DeparturesBoard {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let departureArray = json?["departures"] as? [[String: Any]] else {
            return ([], [], nil)
        }

        let deps = departureArray.prefix(Thresholds.maxDepartures).map { Departure.from(json: $0) }.dedupedForDisplay()
        let favDeps: [Departure]
        if let favArray = json?["favourites"] as? [[String: Any]] {
            favDeps = favArray.map { Departure.from(json: $0) }.dedupedForDisplay()
        } else {
            favDeps = []
        }
        let stale = json?["stale"] as? Bool ?? false
        let staleSince = stale ? (json?["fetchedAt"] as? NSNumber)?.intValue : nil
        return (deps, favDeps, staleSince)
    }

    // MARK: - Formation

    static func fetchFormation(trainNumber: String, date: String, stationId: String, operatorRef: String? = nil) async throws -> Formation? {
        let encodedStation = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        var path = "/v1/formation?train=\(trainNumber)&date=\(date)&stop=\(encodedStation)"
        if let op = operatorRef {
            path += "&operatorRef=\(op)"
        }

        let (data, response) = try await makeRequest(path: path)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return Formation.from(json: json)
    }

    // MARK: - Helpers

    private static func parseStationGroup(_ raw: Any?, mode: TransportMode) -> [Station] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { Station.from(json: $0, mode: mode) }
    }

    /// Tries the hosts in the failover order. A transport error, a timeout,
    /// a 429 or a 5xx moves to the next host; any other answer, an upstream
    /// outage included, is returned as is.
    private static func makeRequest(path: String) async throws -> (Data, URLResponse) {
        let hosts = ApiHost.hosts
        let order = await HostFailover.shared.order(hostCount: hosts.count)
        for (attempt, index) in order.enumerated() {
            try Task.checkCancellation()
            guard let url = URL(string: hosts[index] + path) else { throw TrainAPIError.noData }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = FailoverPolicy.attemptTimeout(attempt: attempt, hostCount: hosts.count)
            let last = attempt == order.count - 1
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if FailoverPolicy.shouldFailover(status: status, body: data) {
                    await HostFailover.shared.recordFailure(index, hostCount: hosts.count)
                    if last { return (data, response) }
                    continue
                }
                await HostFailover.shared.recordSuccess(index, hostCount: hosts.count)
                return (data, response)
            } catch {
                guard FailoverPolicy.shouldFailover(error: error) else { throw TrainAPIError.networkError }
                await HostFailover.shared.recordFailure(index, hostCount: hosts.count)
                if last { throw TrainAPIError.networkError }
            }
        }
        throw TrainAPIError.networkError
    }

    private static func checkHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 { throw TrainAPIError.rateLimited }
        if http.statusCode == 401 { throw TrainAPIError.updateRequired }
        if http.statusCode != 200 && FailoverPolicy.isUpstreamUnavailable(data) {
            throw TrainAPIError.upstreamUnavailable
        }
        if http.statusCode != 200 { throw TrainAPIError.httpError(http.statusCode) }
    }
}
