import ActivityKit
import AppIntents
import Foundation

/// Live Activity contract for a tracking session (Lock Screen + Dynamic
/// Island). Target membership: TrainTimePhone (starts/updates it) and
/// TrainTimeWidgetExtension (renders it). The countdown ticks to the leave-by
/// moment (departure − walk) system-side, so it stays correct with the app
/// suspended or dead; the bar and everything else refresh on each update.
struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Scheduled departure with the live delay applied.
        var effectiveDeparture: Date
        /// The train's terminus; updatable because a protected route leg starts
        /// with the alight stop until a live board match upgrades it.
        var destination: String
        var delay: Int
        var platform: String
        var platformChanged: Bool
        /// TrackingVerdict raw value; a string so the payload stays stable.
        var verdict: String
        /// Whole minutes behind/ahead for the label; sign lives in `verdict`.
        var bufferMinutes: Int
        var walkMinutes: Int?
        var departed: Bool
        /// The diverging tracking bar's two inputs (minutes), same as the in-app
        /// bar: scheduled margin and the margin once the live delay is applied.
        /// The bar redraws on each update rather than gliding, matching Android.
        var schedBuf: Double = 0
        var effectBuf: Double = 0
    }

    var line: String
    var stationName: String
}

/// The walk-vs-departure verdict, mirroring the in-app tracking bar states.
enum TrackingVerdict: String {
    case ahead
    case onTime
    case behind
    case noGps
}

/// Stop button on the Live Activity. It ends the cards itself: when iOS launches
/// the app in the background to run this, no scene and so no view model exists
/// to hear the signal. The stop is also recorded, so a view model that missed
/// the signal (suspended before its main-queue observer ran) applies it on its
/// next appearance. The signal is the analog of Android's notification Stop
/// action feeding `TrackingSessionBus.stopRequests`.
struct StopTrackingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop tracking"

    func perform() async throws -> some IntentResult {
        TrackingStopRequest.record()
        for activity in Activity<TrackingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        NotificationCenter.default.post(name: .stopTrackingRequested, object: nil)
        return .result()
    }
}

/// A Stop pressed on the Live Activity, held until the view model applies it.
enum TrackingStopRequest {
    static let key = "trackingStopRequested"

    static func record(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    /// Reads and clears, so one press stops one session.
    static func take(_ defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: key) else { return false }
        defaults.removeObject(forKey: key)
        return true
    }
}

/// What Back and Stop do to a phone tracking session. Back leaves the tracking
/// screen and keeps the session on the board card when background tracking is
/// on. With it off no Live Activity runs, so Back ends the session. Stop always
/// ends whichever session exists, from every surface that offers it.
enum TrackingSessionLogic {
    enum BackAction: Equatable { case park, end }
    enum StopAction: Equatable { case endImmersive, endParked, nothing }

    static func back(backgroundTracking: Bool) -> BackAction {
        backgroundTracking ? .park : .end
    }

    /// Only one session exists at a time: entering tracking retires a parked one.
    static func stop(immersive: Bool, parked: Bool) -> StopAction {
        if immersive { return .endImmersive }
        if parked { return .endParked }
        return .nothing
    }
}

enum LiveActivityTiming {
    /// How long one payload stays current while the app keeps updating it.
    static let freshFor: TimeInterval = 900

    /// Stale at the effective departure at the latest. ActivityKit re-renders a
    /// card when it goes stale, so a suspended app's card turns to "Departed"
    /// instead of sitting at 0:00 until the app next runs.
    static func staleDate(effectiveDeparture: Date, now: Date) -> Date {
        min(now.addingTimeInterval(freshFor), effectiveDeparture)
    }
}

extension Notification.Name {
    static let stopTrackingRequested = Notification.Name("com.evanjt.traintime.stopTrackingRequested")
}
