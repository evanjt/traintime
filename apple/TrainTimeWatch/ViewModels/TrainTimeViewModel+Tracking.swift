import SwiftUI

extension TrainTimeViewModel {

    // MARK: - Focused Train Update

    internal func updateFocusedTrain() {
        guard var focused = focusedTrain else { return }

        // Match by train number when we have one (a protected shared-route leg
        // carries it), so live platform/delay are adopted even though the leg's
        // destName is the alight stop, not the board's terminus. Fall back to
        // destination for board taps that lack a train number (buses/trams).
        let matches = departures.filter {
            ($0.destination == focused.destination ||
                (focused.trainNumber != nil && $0.trainNumber == focused.trainNumber)) &&
                $0.minutesUntil >= -1
        }
        guard let best = matches.min(by: {
            abs(Double($0.minutesUntil) - focused.minutesUntil) <
            abs(Double($1.minutesUntil) - focused.minutesUntil)
        }) else {
            // A still-future train just isn't on the board yet (a shared route
            // opened early, before it reaches the 20-row horizon). Keep the
            // local countdown; only give up once it has actually departed.
            let nowS = Int(Date().timeIntervalSince1970)
            if nowS < focused.departureTimestamp + PendingRouteLogic.graceSec { return }
            HapticService.shortPulse()
            exitToStationView()
            return
        }

        // Detect platform change
        let oldPlatform = focused.platform
        if best.platform != oldPlatform && !best.platform.isEmpty {
            if best.platformChanged {
                HapticService.doublePulse()
            }
            focused.platform = best.platform
            focused.platformChanged = best.platformChanged
        }

        // A protected route leg starts with the leg's alight stop; the live board
        // row carries the train's real terminus, so adopt it. Always show the
        // train exactly as it reads at the station, never the route destination.
        if !best.destination.isEmpty && best.destination != focused.destination {
            focused.destination = best.destination
        }

        focused.delay = best.delay
        focusedTrain = focused
    }

    // MARK: - Tracking Calculations

    var trackingScheduledBuffer: Double {
        guard let focused = focusedTrain else { return 0 }
        let walkMin = lastWalkTime.map { $0 / 60.0 } ?? GeoUtils.walkMinutes(distanceMeters: lastWalkDist)
        return focused.minutesUntil - walkMin
    }

    var trackingEffectiveBuffer: Double {
        guard let focused = focusedTrain else { return 0 }
        return trackingScheduledBuffer + Double(focused.delay)
    }

    var trackingStatusText: String {
        let buf = trackingEffectiveBuffer
        // Cached coordinates prove nothing about where we are now; no verdict.
        if gpsQuality == .unavailable || gpsQuality == .lastKnown { return String(localized: "No GPS") }
        let absBuf = abs(buf)
        if absBuf < 0.5 { return String(localized: "On time") }
        // Show seconds when close (< 1.5 min), minutes otherwise (matches Garmin)
        let unit = absBuf < 1.5 ? "\(Int(absBuf * 60))s" : String(localized: "\(Int(absBuf)) min")
        return buf > 0 ? String(localized: "\(unit) ahead") : String(localized: "\(unit) behind")
    }

    var trackingStatusColor: Color {
        let buf = trackingEffectiveBuffer
        if gpsQuality == .unavailable || gpsQuality == .lastKnown { return AppColors.barGray }
        if buf > 0.5 { return AppColors.ahead }
        if buf < -0.5 { return AppColors.behind }
        return AppColors.onTime
    }

    /// Direction from user to station in degrees (for arrow rotation)
    var directionToStation: Double? {
        guard let userCoord = location.coordinate,
              let station = currentStation,
              let stationCoord = station.coordinate,
              let heading = location.heading else { return nil }
        let bearing = GeoUtils.bearing(from: userCoord, to: stationCoord)
        // Both bearing and heading are in radians; convert relative angle to degrees
        return (bearing - heading) * 180.0 / .pi
    }

    /// While tracking a shared-route leg, the next ride leg of the same route is
    /// the onward connection: shown under the countdown, tappable to jump onto
    /// it early. Matched by departure time so an unrelated track shows nothing.
    var onwardConnection: OnwardConnection? {
        guard let focused = focusedTrain, let route = PendingRouteStore.shared.pending else { return nil }
        guard let curIdx = route.legs.firstIndex(where: {
            $0.type == .ride && $0.depTs == focused.departureTimestamp
        }) else { return nil }
        let curLeg = route.legs[curIdx]
        guard let nextIdx = route.legs[(curIdx + 1)...].firstIndex(where: { $0.type == .ride }) else { return nil }
        let next = route.legs[nextIdx]
        let changeMinutes = max(0, (next.depTs - curLeg.arrTs) / 60)
        return OnwardConnection(changeStation: curLeg.destName, leg: next, legIndex: nextIdx, changeMinutes: changeMinutes)
    }
}

/// The next ride leg while tracking a shared route: where the user changes, the
/// onward train, and the connection buffer in minutes.
struct OnwardConnection {
    let changeStation: String
    let leg: RouteLeg
    let legIndex: Int
    let changeMinutes: Int
}
