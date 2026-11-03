import ActivityKit
import UserNotifications

/// The one owner of the sound every TrainTime alert asks for. With alert
/// sounds off it names a bundled silent file rather than nil: a nil sound also
/// drops the vibration, and the alert should still buzz.
enum AlertSound {
    static let key = "alertSounds"
    static let silentFile = "silence.caf"

    enum Choice { case standard, silent }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// A trip's own Sound choice wins over the setting until its session ends.
    static func choice(_ defaults: UserDefaults = .standard, session: Bool? = nil) -> Choice {
        TripMute.effective(global: isEnabled(defaults), session: session) ? .standard : .silent
    }

    static func notificationSound(_ choice: Choice = AlertSound.choice()) -> UNNotificationSound {
        switch choice {
        case .standard: return .default
        case .silent: return UNNotificationSound(named: UNNotificationSoundName(silentFile))
        }
    }

    static func liveActivitySound(_ choice: Choice = AlertSound.choice()) -> AlertConfiguration.AlertSound {
        switch choice {
        case .standard: return .default
        case .silent: return .named(silentFile)
        }
    }
}

enum TripMuteLook: Equatable { case on, thisTrip, off }

/// What a Sound or Buzz button shows: the trip's look and the Settings value a
/// hold would flip, since on for this trip reads the same over either.
struct TripMuteState: Equatable {
    let look: TripMuteLook
    let usuallyOn: Bool
}

/// The tracking screen's Sound and Buzz rules: tap decides for this trip, hold
/// for always. Sound only picks the trip's alert sound and Buzz only gates the
/// in-app haptics, so the alerts' own vibration stays with the phone's settings.
enum TripMute {
    static func effective(global: Bool, session: Bool?) -> Bool { session ?? global }

    static func look(global: Bool, session: Bool?) -> TripMuteLook {
        if effective(global: global, session: session) { return .on }
        return global ? .thisTrip : .off
    }

    static func state(global: Bool, session: Bool?) -> TripMuteState {
        TripMuteState(look: look(global: global, session: session), usuallyOn: global)
    }

    /// What a tap did, shown once. Landing back on the setting needs no hint.
    static func tripHint(_ override: Bool?) -> String? {
        guard let override else { return nil }
        return override
            ? String(localized: "On for this trip.")
            : String(localized: "Muted for this trip. Hold to mute always.")
    }

    /// The Settings value, so what a hold flips reads without trying it.
    static func usualCaption(_ state: TripMuteState) -> String {
        state.usuallyOn ? String(localized: "Usually on") : String(localized: "Usually off")
    }

    /// A tap flips what plays now. Landing on what Settings says drops the
    /// override, so a second tap undoes the first.
    static func tapped(global: Bool, session: Bool?) -> Bool? {
        let next = !effective(global: global, session: session)
        return next == global ? nil : next
    }

    /// A hold turns it off for every trip, unless Settings already has it off,
    /// so whatever this trip shows, one hold reaches off. The override goes too.
    static func held(global: Bool, session: Bool?) -> (global: Bool, session: Bool?) {
        (look(global: global, session: session) == .off, nil)
    }
}

/// This trip's Sound and Buzz choices, keyed to the departure they were made for
/// so they can't leak into the next session. nil follows Settings.
struct TripMutes: Equatable {
    var departureTimestamp: Int?
    var sound: Bool?
    var buzz: Bool?

    func scoped(to departureTimestamp: Int?) -> TripMutes {
        guard let departureTimestamp, self.departureTimestamp == departureTimestamp else {
            return TripMutes(departureTimestamp: departureTimestamp)
        }
        return self
    }

    mutating func set(_ field: WritableKeyPath<TripMutes, Bool?>, _ value: Bool?, for departureTimestamp: Int) {
        var next = scoped(to: departureTimestamp)
        next[keyPath: field] = value
        self = next
    }
}
