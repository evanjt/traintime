package com.evanjt.traintime.ui.onboarding

// The interactive walkthrough is a guided coach-mark tour: each step renders a
// real, mocked app surface and spotlights one feature with an anchored callout.
// Stages are the surfaces the steps run over; several steps share a surface.
enum class TourStage { NEARBY, MODE, TRACK, FAVOURITE, PIN, SETTINGS, SHARE, ROUTE_PLAN, WATCH, WIDGET }

data class TourStep(
    val stage: TourStage,
    val title: String,
    val body: String,
    // Tour version this step first appeared in. New installs see every step;
    // an updater sees only steps newer than the version they last finished.
    val introducedIn: Int = 1,
)

// Bump whenever steps are added or materially changed (they get
// introducedIn = this value, so updaters see them again).
// v2: Wear OS released — the watch step announces it instead of teasing it.
const val CURRENT_TOUR_VERSION = 2

// Copy is held inline (not in strings.xml) because each line is tightly bound to
// the step it explains; the rest of the tour (mock data, surfaces) is Kotlin too.
val tourSteps: List<TourStep> = listOf(
    TourStep(
        TourStage.NEARBY,
        "Departures around you",
        "The nearest stations and their live departures. Here's Bern Bahnhof.",
    ),
    TourStep(
        TourStage.MODE,
        "Trains, buses, trams",
        "Switch what you see with the mode chips. Each mode has its own nearby stops.",
    ),
    TourStep(
        TourStage.TRACK,
        "Track a departure",
        "Tap a departure to follow it.",
    ),
    TourStep(
        TourStage.FAVOURITE,
        "Star your lines",
        "Swipe a line right, or hold it, to favourite it.",
    ),
    TourStep(
        TourStage.PIN,
        "Pin a station",
        "Pinned stations lead the list whenever they're among the five nearest, so your " +
            "home station stays first.",
    ),
    TourStep(
        TourStage.SETTINGS,
        "Set your default mode",
        "Pick the mode you ride most. TrainTime opens on it.",
    ),
    TourStep(
        TourStage.SHARE,
        "Bring trips from SBB",
        "Sharing a trip from SBB Mobile? Send it to TrainTime and it picks up your train.",
    ),
    TourStep(
        TourStage.ROUTE_PLAN,
        "Saved routes and reminders",
        "Later trips wait as a saved route. Open it to see every leg, choose which " +
            "connections to track, and get a reminder before departure, timed to your " +
            "walk to the station if you turn that on.",
    ),
    TourStep(
        TourStage.WATCH,
        "Take it to your watch",
        "Wear OS and Garmin both sync live: track on your phone and send a departure " +
            "to your wrist. There's an Apple Watch app for iPhone too.",
        introducedIn = 2,
    ),
    TourStep(
        TourStage.WIDGET,
        "Add the widget",
        "Put your next departures on the home screen.",
    ),
)

// Shown once a departure row has been tapped and the tracking surface is up.
const val TRACK_DETAIL_BODY =
    "Your location and the departure time update live to tell you if you'll make it on foot."

// Shown once a line has been favourited: it appears in the favourites block above and stays
// in the list below.
const val FAVOURITE_DETAIL_BODY = "It now sits above the gold line and still appears in the list below."

// The version an updater effectively last saw. A stored version wins; otherwise
// a legacy user who finished the old (pre-versioning) tour counts as v1, and a
// user who never saw it is 0. Pure for testability.
fun effectiveSeenVersion(hasSeen: Boolean, seenVersion: Int): Int =
    when {
        seenVersion > 0 -> seenVersion
        hasSeen -> 1
        else -> 0
    }

// Steps to run for a user who last saw `effectiveSeen`, up to `current`. A new
// user (0) gets every step; an updater gets only steps newer than what they saw;
// an up-to-date user gets none. Takes the list explicitly so it is unit-testable
// with a synthetic future step.
fun stepsToShow(steps: List<TourStep>, effectiveSeen: Int, current: Int): List<TourStep> =
    steps.filter { it.introducedIn > effectiveSeen && it.introducedIn <= current }

// Progress dots: the TRACK and FAVOURITE steps each expand into a second page
// (live tracking / starred detail), so both sub-pages carry their own dot. Works
// on whatever subset is being shown, so a delta tour without those steps drops
// their extra dots. Pure so the dot arithmetic is unit-testable.
fun tourDotPosition(
    steps: List<TourStep>,
    stepIndex: Int,
    trackingActive: Boolean,
    hasFavourites: Boolean,
): Pair<Int, Int> {
    val trackStep = steps.indexOfFirst { it.stage == TourStage.TRACK }
    val favStep = steps.indexOfFirst { it.stage == TourStage.FAVOURITE }
    var index = stepIndex
    if (trackStep >= 0 && (stepIndex > trackStep || (stepIndex == trackStep && trackingActive))) index++
    if (favStep >= 0 && (stepIndex > favStep || (stepIndex == favStep && hasFavourites))) index++
    val subPages = (if (trackStep >= 0) 1 else 0) + (if (favStep >= 0) 1 else 0)
    return index to (steps.size + subPages)
}
