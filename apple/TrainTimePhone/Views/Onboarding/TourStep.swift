import Foundation

// Guided coach-mark tour: each step renders a real, mocked app surface and spotlights one
// feature with an anchored callout. Stages are the surfaces; several steps share a surface.
// Peer of the Android ui/onboarding/TourStep.kt.
enum TourStage {
    case nearby, mode, track, background, favourite, pin, settings, share, route, watch, widget
}

struct TourStep: Identifiable {
    let id = UUID()
    let stage: TourStage
    let title: String
    let body: String
    // Tour version this step first appeared in. New installs see every step; an
    // updater sees only steps newer than the version they last finished.
    var introducedIn: Int = 1
}

// Bump whenever steps are added (new steps get introducedIn = this value).
// v2: tracking survives backgrounding, so the background-location disclosure
// reaches existing users as a one-step delta tour on first open after updating.
let currentTourVersion = 2

// The version an updater effectively last saw. A stored version wins; otherwise a
// legacy user who finished the old (pre-versioning) tour counts as v1, and a user
// who never saw it is 0.
func effectiveSeenVersion(hasSeen: Bool, seenVersion: Int) -> Int {
    if seenVersion > 0 { return seenVersion }
    return hasSeen ? 1 : 0
}

// Steps to run for a user who last saw `effectiveSeen`, up to `current`. New user
// (0) → every step; updater → only steps newer than what they saw; up-to-date →
// none. Takes the list explicitly so it is unit-testable with a synthetic step.
func stepsToShow(_ steps: [TourStep], effectiveSeen: Int, current: Int) -> [TourStep] {
    steps.filter { $0.introducedIn > effectiveSeen && $0.introducedIn <= current }
}

// Copy is held inline (not Localizable), tightly bound to the step it explains. Terse,
// second-person, no marketing tone.
let tourSteps: [TourStep] = [
    TourStep(stage: .nearby, title: String(localized: "Departures around you"),
             body: String(localized: "The nearest stations and their live departures. Here's Bern Bahnhof.")),
    TourStep(stage: .mode, title: String(localized: "Trains, buses, trams"),
             body: String(localized: "Switch what you see with the mode chips. Each mode has its own nearby stops.")),
    TourStep(stage: .track, title: String(localized: "Track a departure"),
             body: String(localized: "Tap a departure to follow it.")),
    // Straight after .track: the user has just learned what tracking is, which is
    // the only place the background disclosure makes sense.
    TourStep(stage: .background, title: String(localized: "Tracking keeps going"),
             body: String(localized: "Leave the app and your train keeps counting down on the Lock Screen, with an alert when it's time to leave. TrainTime uses your location in the background to do it, only while you're tracking. Turn it off any time in Settings."),
             introducedIn: 2),
    TourStep(stage: .favourite, title: String(localized: "Star your lines"),
             body: String(localized: "Swipe a line right, or hold it, to favourite it.")),
    TourStep(stage: .pin, title: String(localized: "Pin a station"),
             body: String(localized: "Pinned stations lead the list whenever they're among the five nearest, so your home station stays first.")),
    TourStep(stage: .settings, title: String(localized: "Set your default mode"),
             body: String(localized: "Pick the mode you ride most. TrainTime opens on it.")),
    TourStep(stage: .share, title: String(localized: "Bring trips from SBB"),
             body: String(localized: "Sharing a trip from SBB Mobile? Send it to TrainTime and it picks up your train.")),
    TourStep(stage: .route, title: String(localized: "Saved routes and reminders"),
             body: String(localized: "Later trips wait as a saved route. Open it to see every leg, choose which connections to track, and get a reminder before departure, timed to your walk to the station if you turn that on.")),
    TourStep(stage: .watch, title: String(localized: "Take it to your watch"),
             body: String(localized: "Have a Garmin? Track on your phone and send a departure to your wrist. There's an Apple Watch app too.")),
    TourStep(stage: .widget, title: String(localized: "Add the widget"),
             body: String(localized: "Put your next departures on the home screen.")),
]

// Shown once a departure row has been tapped and the tracking surface is up.
let tourTrackDetailBody =
    String(localized: "Your location and the departure time update live to tell you if you'll make it on foot.")

// Shown once a line has been favourited: it appears in the favourites block above and stays in
// the list below.
let tourFavouriteDetailBody = String(localized: "It now sits above the gold line and still appears in the list below.")

let connectIQStoreURL = URL(string: "https://apps.garmin.com/en-CH/apps/c70bbfae-846a-4d00-9e96-d485217035fb")!

// Tracking demo: a short, looping countdown so the bar and status visibly shift.
let tourTrackRunwaySec = 165
let tourTrackDistanceM = 130.0
