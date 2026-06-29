package com.evanjt.traintime.ui.onboarding

// The interactive walkthrough is a guided coach-mark tour: each step renders a
// real, mocked app surface and spotlights one feature with an anchored callout.
// Stages are the surfaces the steps run over; several steps share a surface.
enum class TourStage { NEARBY, TRACK, FAVOURITE, PIN, SETTINGS, WIDGET }

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
        "TrainTime finds the stations nearest you and shows their live departures. " +
            "Here's Bern Bahnhof.",
    ),
    TourStep(
        TourStage.TRACK,
        "Track a departure",
        "Tap a departure to follow it.",
    ),
    TourStep(
        TourStage.FAVOURITE,
        "Star your lines",
        "Tap a line to favourite it. Favourites jump to the top so your usual trains are always first.",
    ),
    TourStep(
        TourStage.PIN,
        "Pin a station",
        "Pin a station and it leads the list whenever it's among the five nearest — " +
            "handy when you're standing closer to a smaller stop.",
    ),
    TourStep(
        TourStage.SETTINGS,
        "Choose your default mode",
        "In Settings, pick the mode you ride most. Train, bus or tram — it's what you'll see first.",
    ),
    TourStep(
        TourStage.WIDGET,
        "Add the widget",
        "Put your next departures on your home screen — favourites and the next trains, at a glance.",
    ),
)

// Shown once the IC1 row has been tapped and the tracking surface is up.
const val TRACK_DETAIL_BODY =
    "A live countdown, the platform, and how comfortably you'll make it on foot."
