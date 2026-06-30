import Foundation

// Guided coach-mark tour: each step renders a real, mocked app surface and spotlights one
// feature with an anchored callout. Stages are the surfaces; several steps share a surface.
// Peer of the Android ui/onboarding/TourStep.kt.
enum TourStage {
    case nearby, track, favourite, pin, settings, watch, widget
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
             body: "Tap a line to favourite it. Favourites jump to the top."),
    TourStep(stage: .pin, title: "Pin a station",
             body: "Pinned stations lead the list whenever they're among the five nearest."),
    TourStep(stage: .settings, title: "Set your default mode",
             body: "Pick the mode you ride most. It shows first."),
    TourStep(stage: .watch, title: "Sync your watch",
             body: "Pair a Garmin or Apple Watch and your tracked train, mode and station mirror "
                 + "to your wrist. The icon turns green when it's live."),
    TourStep(stage: .widget, title: "Add the widget",
             body: "Put your next departures on the home screen."),
]

// Shown once a departure row has been tapped and the tracking surface is up.
let tourTrackDetailBody = "A live countdown, the platform, and your walk time."

let connectIQStoreURL = URL(string: "https://apps.garmin.com/apps/c70bbfae-846a-4d00-9e96-d485217035fb")!
