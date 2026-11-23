import Foundation

/// A coverage area the app serves: its box, the zone its departure times read in, the prefix its
/// station ids carry, and the features its data supports. Adding a region is adding one entry to
/// `Region.all`; no call site names a country. The list matches the backend and the other clients.
struct Region: Equatable {
    struct Bounds: Equatable {
        let latMin: Double
        let latMax: Double
        let lonMin: Double
        let lonMax: Double

        func contains(lat: Double, lon: Double) -> Bool {
            lat >= latMin && lat <= latMax && lon >= lonMin && lon <= lonMax
        }
    }

    let id: String
    let bounds: Bounds
    let timeZone: TimeZone
    /// Prefix of this region's station ids. Empty for the region whose ids are bare.
    let idPrefix: String
    /// Train formation data is available for this region's departures.
    let formation: Bool
    /// Trips shared from the SBB app start in this region.
    let sbbShare: Bool

    static let switzerland = Region(
        id: "ch",
        bounds: Bounds(latMin: 45.8, latMax: 47.8, lonMin: 5.9, lonMax: 10.5),
        timeZone: TimeZone(identifier: "Europe/Zurich")!,
        idPrefix: "",
        formation: true,
        sbbShare: true
    )

    static let melbourne = Region(
        id: "au-vic",
        bounds: Bounds(latMin: -38.50, latMax: -37.40, lonMin: 144.40, lonMax: 145.70),
        timeZone: TimeZone(identifier: "Australia/Melbourne")!,
        idPrefix: "au-vic-",
        formation: false,
        sbbShare: false
    )

    static let all: [Region] = [switzerland, melbourne]

    /// The region whose box holds the point, or nil outside every region.
    static func at(lat: Double, lon: Double) -> Region? {
        all.first { $0.bounds.contains(lat: lat, lon: lon) }
    }

    /// True when some region covers the point.
    static func covers(lat: Double, lon: Double) -> Bool {
        at(lat: lat, lon: lon) != nil
    }

    /// The region a station id belongs to: the one whose prefix it carries, else the region whose
    /// ids are bare. Nil for a missing or empty id.
    static func forStationId(_ id: String?) -> Region? {
        guard let id, !id.isEmpty else { return nil }
        if let prefixed = all.first(where: { !$0.idPrefix.isEmpty && id.hasPrefix($0.idPrefix) }) {
            return prefixed
        }
        return all.first { $0.idPrefix.isEmpty }
    }

    /// The zone a station's times read in: its region's, or the device's when the id is unknown.
    static func timeZone(forStationId id: String?) -> TimeZone {
        forStationId(id)?.timeZone ?? .current
    }

    /// "HH:mm" for a departure at a station, in the station's region zone.
    static func clockTime(_ timestamp: Int, stationId: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone(forStationId: stationId)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    /// "yyyy-MM-dd" service date for a formation lookup at a station, in the station's region zone.
    static func serviceDate(_ date: Date, stationId: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone(forStationId: stationId)
        return formatter.string(from: date)
    }

    /// Whether formation is fetched for a departure at this station.
    static func hasFormation(stationId: String?) -> Bool {
        forStationId(stationId)?.formation ?? false
    }
}

/// What a location fix does to an empty board: search for stations, or show the out-of-coverage
/// state. A board that already has stations keeps them, so a fix just over a border does not clear it.
enum CoverageGate: Equatable {
    case search
    case outOfCoverage

    static func onFix(lat: Double, lon: Double, hasStations: Bool) -> CoverageGate {
        Region.covers(lat: lat, lon: lon) || hasStations ? .search : .outOfCoverage
    }
}
