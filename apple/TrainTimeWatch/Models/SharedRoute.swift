import Foundation

// Port of android/core data/sbb/SharedRoute.kt + data/model/PendingRoute.kt +
// domain/PendingRouteLogic.kt. One file so every model rides one target
// membership (phone + watch).

enum LegType: String, Codable {
    case ride = "RIDE"
    case walk = "WALK"
}

/// One leg of a shared SBB Mobile trip. Ride legs carry the train identity
/// split as the recon publishes it: category "IR", lineNumber "90",
/// trainNumber "1820". Departure.lineNumber is the concatenated "IR90" form,
/// so matching normalises (see matchDeparture).
struct RouteLeg: Codable, Equatable {
    let type: LegType
    var originId: String?
    let originName: String
    var originLat: Double?
    var originLon: Double?
    var destId: String?
    let destName: String
    var destLat: Double?
    var destLon: Double?
    let depTs: Int
    let arrTs: Int
    var category: String?
    var lineNumber: String?
    var trainNumber: String?

    var durationSec: Int { arrTs - depTs }

    /// A leg can only be live-tracked if it's a Swiss ride with a station id.
    /// Walk legs and connections outside Switzerland have no departure board.
    var isTrackable: Bool {
        guard type == .ride, originId != nil, let lat = originLat, let lon = originLon else { return false }
        return SwissBounds.contains(lat: lat, lon: lon)
    }
}

struct SharedRoute: Equatable {
    let legs: [RouteLeg]
    let sourceBlob: String

    /// Where the trip actually ends: the last leg's destination, walk
    /// included ("Lausanne, gare"), not the last train's alighting stop.
    var finalDestinationName: String {
        legs.last?.destName ?? ""
    }

    /// The leg worth acting on now. First ride leg still catchable (60s grace
    /// matches the "now" display threshold); a departed leg is skipped, so
    /// mid-route shares naturally select the next connection. Nil when every
    /// ride has left, trip underway on its last leg or finished.
    func targetRideLegIndex(now: Int) -> Int? {
        legs.firstIndex { $0.type == .ride && $0.depTs >= now - 60 }
    }

    /// A one-leg route synthesised from a live board departure, so a departure can
    /// be saved for a reminder without an SBB share. Origin (id + coords) comes
    /// from the station whose board it is; that's what the distance-aware reminder
    /// needs. Peer of SharedRoute.forDeparture in SharedRoute.kt.
    static func forDeparture(station: Station, departure: Departure) -> SharedRoute {
        single(
            originId: station.id,
            originName: station.name ?? "",
            originLat: station.lat,
            originLon: station.lon,
            destName: departure.destination,
            depTs: departure.departureTimestamp ?? 0,
            lineNumber: departure.lineNumber,
            trainNumber: departure.trainNumber
        )
    }

    /// The single-ride-leg builder shared by the board save and the watch's
    /// remind-on-phone command. lineNumber keeps the concatenated board form
    /// ("IR90") with category nil, so the chip/fingerprint render it directly and
    /// matchDeparture still round-trips it; arrTs = depTs (unused for one leg).
    static func single(
        originId: String?,
        originName: String,
        originLat: Double?,
        originLon: Double?,
        destName: String,
        depTs: Int,
        lineNumber: String,
        trainNumber: String?
    ) -> SharedRoute {
        let leg = RouteLeg(
            type: .ride,
            originId: originId,
            originName: originName,
            originLat: originLat,
            originLon: originLon,
            destId: nil,
            destName: destName,
            destLat: nil,
            destLon: nil,
            depTs: depTs,
            arrTs: depTs,
            category: nil,
            lineNumber: lineNumber,
            trainNumber: trainNumber
        )
        return SharedRoute(legs: [leg], sourceBlob: "")
    }
}

/// A shared SBB route queued for later: the target leg wasn't on the live
/// departure board yet (too far in the future), so tracking would have died
/// on the first poll. Phone-owned; the watch receives a read-only mirror.
struct PendingRoute: Codable, Equatable {
    static let statusSaved = "saved"
    static let statusTracking = "tracking"

    let id: String
    let legs: [RouteLeg]
    let finalDestination: String
    var cursor: Int
    var status: String
    let createdTs: Int
    var sourceUrl: String?
    /// Legs the user switched off in the route view: no reminder, no auto-resume
    /// offer. The route stays visible and any leg can still be tracked by hand.
    /// Optional so routes saved before this field decode cleanly.
    var mutedLegIndices: [Int]?

    var currentLeg: RouteLeg? {
        guard cursor < legs.count, legs[cursor].type == .ride else { return nil }
        return legs[cursor]
    }

    func isLegMuted(_ index: Int) -> Bool { (mutedLegIndices ?? []).contains(index) }

    static func from(route: SharedRoute, targetLegIndex: Int, id: String, createdTs: Int, sourceUrl: String?) -> PendingRoute {
        PendingRoute(
            id: id,
            legs: route.legs,
            finalDestination: route.finalDestinationName,
            cursor: targetLegIndex,
            status: statusSaved,
            createdTs: createdTs,
            sourceUrl: sourceUrl
        )
    }
}

/// Pure lifecycle rules for a pending route. Everything is derived from the
/// clock, so the same call is safe on foreground, on timer ticks, and after
/// tracking ends. Event plumbing only makes advancement prompt, never
/// correct. All functions take `now` explicitly for testability.
enum PendingRouteLogic {
    /// Matches the departed auto-exit (minutesUntil < -1) so a leg isn't
    /// declared missed while its tracking session could still be running.
    static let graceSec = 90

    /// Notification lead for the first leg of a saved route: at least 15 min
    /// before departure, more when a preceding walk leg needs it. Both leads
    /// are user-configurable (Settings), the notifier passes the chosen value.
    static let minLeadSec = 15 * 60
    static let walkMarginSec = 5 * 60

    /// Lead for a later connection, when the traveller is already moving. Much
    /// shorter than the initial reminder and set independently.
    static let connectionLeadSec = 3 * 60

    /// Cap on the first-leg lead so a distance-aware reminder saved from far
    /// away never schedules absurdly early.
    static let maxLeadSec = 90 * 60

    /// A route is only offered for one-tap resume this close to departure,
    /// roughly when the train can appear on the 20-row board.
    static let resumeWindowSec = 45 * 60

    /// Advance the cursor past every ride leg that has already left. Nil
    /// means no viable leg remains and the route should be cleared.
    static func normalize(_ route: PendingRoute, now: Int) -> PendingRoute? {
        var cursor = route.cursor
        while cursor < route.legs.count {
            let leg = route.legs[cursor]
            if leg.type == .ride && leg.depTs >= now - graceSec { break }
            cursor += 1
        }
        guard cursor < route.legs.count else { return nil }
        if cursor == route.cursor { return route }
        var advanced = route
        advanced.cursor = cursor
        advanced.status = PendingRoute.statusSaved
        return advanced
    }

    /// A ride leg with an earlier ride leg in the route is a connection: the
    /// traveller has already boarded once, so a short reminder suffices.
    static func isConnectionLeg(_ route: PendingRoute) -> Bool {
        guard route.cursor < route.legs.count else { return false }
        return route.legs.prefix(route.cursor).contains { $0.type == .ride }
    }

    /// When `userDistanceMeters` is supplied (distance-aware mode), the first-leg
    /// lead becomes the walk time to the origin station plus `savedLeadSec` as a
    /// buffer, capped at `maxLeadSec`. Nil distance keeps the static behaviour.
    /// Connection legs always use the short static connection lead.
    ///
    /// `walkSecondsOverride` wins over the straight-line estimate: it's the routed
    /// walk time (MKDirections) the phone measures live, so the lead matches what
    /// tracking shows on arrival instead of under-counting a straight line.
    static func notifyTs(
        _ route: PendingRoute,
        savedLeadSec: Int = minLeadSec,
        connectionLeadSec: Int = connectionLeadSec,
        userDistanceMeters: Double? = nil,
        walkSecondsOverride: Int? = nil
    ) -> Int? {
        guard let leg = route.currentLeg else { return nil }
        guard leg.isTrackable, !route.isLegMuted(route.cursor) else { return nil }
        if isConnectionLeg(route) { return leg.depTs - connectionLeadSec }
        if let walkSec = walkSecondsOverride {
            let lead = min(walkSec + savedLeadSec, maxLeadSec)
            return leg.depTs - lead
        }
        if let distance = userDistanceMeters {
            let walkSec = Int(GeoUtils.walkMinutes(distanceMeters: distance) * 60)
            let lead = min(walkSec + savedLeadSec, maxLeadSec)
            return leg.depTs - lead
        }
        let walk = route.cursor > 0 ? route.legs[route.cursor - 1] : nil
        let walkLead = (walk?.type == .walk) ? (walk?.durationSec ?? 0) : 0
        let lead = max(savedLeadSec, walkLead + walkMarginSec)
        return leg.depTs - lead
    }

    static func isResumable(_ route: PendingRoute, now: Int) -> Bool {
        guard let leg = route.currentLeg else { return false }
        guard leg.isTrackable, !route.isLegMuted(route.cursor) else { return false }
        return leg.depTs - now <= resumeWindowSec && leg.depTs >= now - graceSec
    }

    /// Same trip shared twice is idempotent; a different trip needs the
    /// user's confirmation before replacing.
    static func fingerprint(_ legs: [RouteLeg]) -> String {
        guard let leg = legs.first(where: { $0.type == .ride }) else { return "" }
        let train = leg.trainNumber ?? "\(leg.category ?? "")\(leg.lineNumber ?? "")"
        return "\(train)|\(leg.depTs)"
    }

    /// Tracking for `endedDepTs` finished (departed, or user exited). Only a
    /// route that was tracking that exact leg reacts: after departure the
    /// cursor moves on, an early manual exit reverts to saved on the same
    /// leg. Unrelated tracking sessions never touch pending state.
    static func advancedAfterTracking(_ route: PendingRoute, endedDepTs: Int, now: Int) -> PendingRoute? {
        guard route.status == PendingRoute.statusTracking else { return route }
        guard let leg = route.currentLeg else { return normalize(route, now: now) }
        guard leg.depTs == endedDepTs else { return route }
        if now < leg.depTs - graceSec {
            var reverted = route
            reverted.status = PendingRoute.statusSaved
            return reverted
        }
        var advanced = route
        advanced.cursor = route.cursor + 1
        advanced.status = PendingRoute.statusSaved
        return normalize(advanced, now: now)
    }
}

/// Finds the shared leg on a live departure board. Primary key is the exact
/// train (journey number + scheduled time); fallback tolerates a missing
/// trainNumber by normalising the line ("IR" + "90" vs Departure's "IR90").
/// Never matches on destination: the leg's destName is where the user
/// alights, Departure.destination is the train's terminus.
func matchDeparture(_ departures: [Departure], leg: RouteLeg) -> Departure? {
    guard leg.type == .ride else { return nil }
    if let train = leg.trainNumber,
       let exact = departures.first(where: { $0.trainNumber == train && $0.departureTimestamp == leg.depTs }) {
        return exact
    }
    let legLine = "\(leg.category ?? "")\(leg.lineNumber ?? "")".lowercased()
    guard !legLine.isEmpty else { return nil }
    return departures.first { dep in
        guard let ts = dep.departureTimestamp, abs(ts - leg.depTs) <= 60 else { return false }
        let line = dep.lineNumber.lowercased()
        return line == legLine || line == leg.lineNumber?.lowercased()
    }
}
