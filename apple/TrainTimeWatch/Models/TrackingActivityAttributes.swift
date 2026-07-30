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
    /// Left edge of the progress axis: when tracking began.
    var startedAt: Date
}

/// The walk-vs-departure verdict, mirroring the in-app tracking bar states.
enum TrackingVerdict: String {
    case ahead
    case onTime
    case behind
    case noGps
}

/// Stop button on the Live Activity. `LiveActivityIntent` runs in the app
/// process, so it only signals the running view model — the analog of Android's
/// notification Stop action feeding `TrackingSessionBus.stopRequests`. If the app
/// was terminated, its launch re-runs `reapOrphanLiveActivities`, which ends the
/// stray card anyway, so a missed signal still tears the card down.
struct StopTrackingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop tracking"

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .stopTrackingRequested, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let stopTrackingRequested = Notification.Name("com.evanjt.traintime.stopTrackingRequested")
}
