package com.evanjt.traintime.ui.onboarding

// The interactive walkthrough is a guided coach-mark tour: each step renders a
// real, mocked app surface and spotlights one feature with an anchored callout.
// Stages are the surfaces the steps run over; several steps share a surface.
enum class TourStage { NEARBY, TRACK, FAVOURITE, PIN, SETTINGS, WATCH, WIDGET }

data class TourStep(
    val stage: TourStage,
    val title: String,
    val body: String,
)

// Copy is held inline (not in strings.xml) because each line is tightly bound to
// the step it explains; the rest of the tour (mock data, surfaces) is Kotlin too.
val tourSteps: List<TourStep> = listOf(
    TourStep(
        TourStage.NEARBY,
        "Departures around you",
        "The nearest stations and their live departures. Here's Bern Bahnhof.",
    ),
    TourStep(
        TourStage.TRACK,
        "Track a departure",
        "Tap a departure to follow it.",
    ),
    TourStep(
        TourStage.FAVOURITE,
        "Star your lines",
        "Hold a line to favourite it.",
    ),
    TourStep(
        TourStage.PIN,
        "Pin a station",
        "Pinned stations lead the list whenever they're among the five nearest. So when " +
            "you're between Bern Bahnhof and Wankdorf, Bern stays first for a quick glance on launch.",
    ),
    TourStep(
        TourStage.SETTINGS,
        "Set your default mode",
        "Pick the mode you ride most. It shows first.",
    ),
    TourStep(
        TourStage.WATCH,
        "Take it to your watch",
        "Have a Garmin? Track on your phone and send a departure to your wrist. " +
            "Wear OS is coming, and there's an Apple Watch app for iPhone.",
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
const val FAVOURITE_DETAIL_BODY = "It's now pinned above and still in the list below."
