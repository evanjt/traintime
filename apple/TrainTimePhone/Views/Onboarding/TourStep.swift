import Foundation

// Guided coach-mark tour: each step renders a real, mocked app surface and spotlights one
// feature with an anchored callout. Stages are the surfaces; several steps share a surface.
// Peer of the Android ui/onboarding/TourStep.kt.
enum TourStage {
    case nearby, track, favourite, pin, settings, share, route, watch, widget
}

struct TourStep: Identifiable {
    let id = UUID()
    let stage: TourStage
    let title: String
    let body: String
}

// Copy is held inline (not Localizable), tightly bound to the step it explains. Terse,
// second-person, no marketing tone.
let tourSteps: [TourStep] = [
    TourStep(stage: .nearby, title: "Departures around you",
             body: "The nearest stations and their live departures. Here's Bern Bahnhof."),
    TourStep(stage: .track, title: "Track a departure",
             body: "Tap a departure to follow it."),
    TourStep(stage: .favourite, title: "Star your lines",
             body: "Hold a line to favourite it."),
    TourStep(stage: .pin, title: "Pin a station",
             body: "Pinned stations lead the list whenever they're among the five nearest. So when "
                 + "you're between Bern Bahnhof and Wankdorf, Bern stays first for a quick glance on launch."),
    TourStep(stage: .settings, title: "Set your default mode",
             body: "Pick the mode you ride most. It shows first."),
    TourStep(stage: .share, title: "Bring trips from SBB",
             body: "Sharing a trip from SBB Mobile? Send it to TrainTime and it picks up your train."),
    TourStep(stage: .route, title: "Your route, saved and reminded",
             body: "Later trips wait as a saved route. Open it to see every leg, choose which "
                 + "connections to track, and get a reminder before departure."),
    TourStep(stage: .watch, title: "Take it to your watch",
             body: "Have a Garmin? Track on your phone and send a departure to your wrist. "
                 + "There's an Apple Watch app too."),
    TourStep(stage: .widget, title: "Add the widget",
             body: "Put your next departures on the home screen."),
]

// Shown once a departure row has been tapped and the tracking surface is up.
let tourTrackDetailBody =
    "Your location and the departure time update live to tell you if you'll make it on foot."

// Shown once a line has been favourited: it appears in the favourites block above and stays in
// the list below.
let tourFavouriteDetailBody = "It's now pinned above and still in the list below."

let connectIQStoreURL = URL(string: "https://apps.garmin.com/en-CH/apps/c70bbfae-846a-4d00-9e96-d485217035fb")!

// Tracking demo: a short, looping countdown so the bar and status visibly shift.
let tourTrackRunwaySec = 165
let tourTrackDistanceM = 130.0
