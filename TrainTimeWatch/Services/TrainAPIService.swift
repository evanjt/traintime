import Foundation

enum TrainAPIError: Error {
    case rateLimited
    case httpError(Int)
    case noData
}

struct TrainAPIService {
    static func fetchNearbyStations(lat: Double, lon: Double) async throws -> [Station] {
        let urlString = "https://search.ch/timetable/api/completion.en.json"
            + "?latlon=\(lat),\(lon)"
            + "&accuracy=10000&show_ids=1"

        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw TrainAPIError.rateLimited }
            if http.statusCode != 200 { throw TrainAPIError.httpError(http.statusCode) }
        }

        let decoded = try JSONDecoder().decode([Station].self, from: data)
        let valid = decoded.filter { $0.id != nil }
        return Array(valid.prefix(5))
    }

    static func fetchDepartures(stationId: String) async throws -> [Departure] {
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        let urlString = "https://transport.opendata.ch/v1/stationboard"
            + "?id=\(encoded)"
            + "&limit=5"
            + "&fields[]=stationboard/to"
            + "&fields[]=stationboard/category"
            + "&fields[]=stationboard/stop/departureTimestamp"
            + "&fields[]=stationboard/stop/delay"
            + "&fields[]=stationboard/stop/platform"
            + "&fields[]=stationboard/stop/prognosis/platform"

        guard let url = URL(string: urlString) else { throw TrainAPIError.noData }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw TrainAPIError.rateLimited }
            if http.statusCode != 200 { throw TrainAPIError.httpError(http.statusCode) }
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let stationboard = json?["stationboard"] as? [[String: Any]] else {
            return []
        }

        let now = Int(Date().timeIntervalSince1970)
        var departures: [Departure] = []

        for entry in stationboard.prefix(5) {
            let destination = entry["to"] as? String ?? "?"
            let stop = entry["stop"] as? [String: Any] ?? [:]

            // Platform logic
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

            // Minutes until departure
            var minutesUntil = -1
            if let depTs = stop["departureTimestamp"] as? Int {
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
                delay: delay,
                platform: platform,
                platformChanged: platformChanged
            ))
        }

        return departures
    }
}
