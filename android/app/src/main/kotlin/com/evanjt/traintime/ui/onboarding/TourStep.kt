package com.evanjt.traintime.ui.onboarding

import androidx.annotation.StringRes
import com.evanjt.traintime.R

// The interactive walkthrough is a guided coach-mark tour: each step renders a
// real, mocked app surface and spotlights one feature with an anchored callout.
// Stages are the surfaces the steps run over; several steps share a surface.
enum class TourStage { NEARBY, MODE, TRACK, BACKGROUND, FAVOURITE, PIN, SETTINGS, SHARE, ROUTE_PLAN, WATCH, WIDGET }

data class TourStep(
    val stage: TourStage,
    @StringRes val titleRes: Int,
    @StringRes val bodyRes: Int,
    // Tour version this step first appeared in. New installs see every step;
    // an updater sees only steps newer than the version they last finished.
    val introducedIn: Int = 1,
)

// Bump whenever steps are added or materially changed (they get
// introducedIn = this value, so updaters see them again).
// v2: Wear OS released — the watch step announces it instead of teasing it.
// v3: tracking survives backgrounding, so the background-location disclosure
// reaches existing users as a one-step delta tour on first open after updating.
const val CURRENT_TOUR_VERSION = 3

// Each step's copy is a string resource, so the tour localises with the rest of
// the app. The step-to-surface binding stays in Kotlin.
val tourSteps: List<TourStep> = listOf(
    TourStep(TourStage.NEARBY, R.string.tour_nearby_title, R.string.tour_nearby_body),
    TourStep(TourStage.MODE, R.string.tour_modes_title, R.string.tour_modes_body),
    TourStep(TourStage.TRACK, R.string.tour_track_title, R.string.tour_track_body),
    // Straight after TRACK: the user has just learned what tracking is, which is
    // the only place the background disclosure makes sense.
    TourStep(
        TourStage.BACKGROUND,
        R.string.tour_background_title,
        R.string.tour_background_body,
        introducedIn = 3,
    ),
    TourStep(TourStage.FAVOURITE, R.string.tour_star_title, R.string.tour_star_body),
    TourStep(TourStage.PIN, R.string.tour_pin_title, R.string.tour_pin_body),
    TourStep(TourStage.SETTINGS, R.string.tour_mode_title, R.string.tour_mode_body),
    TourStep(TourStage.SHARE, R.string.tour_sbb_title, R.string.tour_sbb_body),
    TourStep(TourStage.ROUTE_PLAN, R.string.tour_routes_title, R.string.tour_routes_body),
    TourStep(TourStage.WATCH, R.string.tour_watch_title, R.string.tour_watch_body, introducedIn = 2),
    TourStep(TourStage.WIDGET, R.string.tour_widget_title, R.string.tour_widget_body),
)

// Shown once a departure row has been tapped and the tracking surface is up.
@StringRes
val TRACK_DETAIL_BODY = R.string.tour_tracking_extra

// Shown once a line has been favourited: it appears in the favourites block above and stays
// in the list below.
@StringRes
val FAVOURITE_DETAIL_BODY = R.string.tour_starred_extra

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
