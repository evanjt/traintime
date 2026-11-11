package com.evanjt.traintime.ui.adaptive

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.TransportMode
import kotlin.math.floor
import kotlin.math.min

// BOARD and TRACKING are the compact flow, one screen at a time. SIDE_BY_SIDE
// gives each pane a phone's width. CARD keeps the board readable and lays
// tracking over its right side at one of three stops.
enum class PaneMode { BOARD, TRACKING, SIDE_BY_SIDE, CARD }

enum class CardStop { PEEK, HALF, FULL }

// The board spans 0 to boardDp and tracking, or the hint, starts at
// detailStartDp. A gap between them is the divider or an occluded fold.
data class PaneLayout(
    val mode: PaneMode,
    val stop: CardStop?,
    val boardDp: Float,
    val detailStartDp: Float,
    val onFold: Boolean,
)

// The board's normal width. Two of them side by side need 800.
const val BOARD_WIDTH_DP = 400f

// The folded iPhone Duo's width, the widest the board grows beside the Peek card.
const val BOARD_PEEK_MAX_DP = 466f
const val PEEK_CARD_MIN_DP = 200f

// The narrowest window tracking is drawn in full on a compact phone.
const val TRACKING_MIN_DP = 360f

const val WIDE_MIN_WIDTH_DP = 600f
const val COMPACT_HEIGHT_DP = 480f
private const val DIVIDER_DP = 1f

// The one decision for the window. A compact window, or a landscape phone too
// short for a second pane, keeps the board, then tracking full-screen, and
// tracking scrolls. Room for two board-width panes splits at the middle, or on
// the fold. Any other wide window is card mode: Peek while nothing is tracked,
// Half once tracking starts unless the user chose another stop. State 3
// (inactive) shows the board, or the idle split, under its scrim.
fun paneLayout(
    widthDp: Float,
    heightDp: Float,
    fold: VerticalFold?,
    appState: Int,
    stop: CardStop? = null,
): PaneLayout {
    val tracking = appState == 2
    if (widthDp < WIDE_MIN_WIDTH_DP || heightDp < COMPACT_HEIGHT_DP) {
        return if (tracking) {
            PaneLayout(PaneMode.TRACKING, null, 0f, 0f, onFold = false)
        } else {
            PaneLayout(PaneMode.BOARD, null, widthDp, widthDp, onFold = false)
        }
    }
    val crease = fold?.takeIf { it.startDp > 0f && it.endDp < widthDp }
    if (widthDp >= 2 * BOARD_WIDTH_DP) {
        if (crease != null) return PaneLayout(PaneMode.SIDE_BY_SIDE, null, crease.startDp, crease.endDp, onFold = true)
        val board = floor((widthDp - DIVIDER_DP) / 2)
        return PaneLayout(PaneMode.SIDE_BY_SIDE, null, board, board + DIVIDER_DP, onFold = false)
    }
    val at = if (tracking) stop ?: CardStop.HALF else CardStop.PEEK
    val edge = cardEdge(widthDp, crease, at)
    return PaneLayout(PaneMode.CARD, at, edge, edge, onFold = false)
}

private fun cardEdge(widthDp: Float, crease: VerticalFold?, stop: CardStop): Float {
    val edge = when (stop) {
        CardStop.PEEK -> min(BOARD_PEEK_MAX_DP, widthDp - PEEK_CARD_MIN_DP)
        CardStop.HALF -> widthDp - TRACKING_MIN_DP
        CardStop.FULL -> 0f
    }
    // Nothing draws under an occluded strip, so an edge inside one moves to its
    // start: the card grows and never drops below its minimum.
    return if (crease != null && edge > crease.startDp && edge < crease.endDp) crease.startDp else edge
}

// Where the card's leading edge rests at each stop, the anchors it is dragged
// between. The same edges paneLayout gives, so a drag settles where a tap would.
fun cardEdges(widthDp: Float, fold: VerticalFold?): Map<CardStop, Float> {
    val crease = fold?.takeIf { it.startDp > 0f && it.endDp < widthDp }
    return CardStop.entries.associateWith { cardEdge(widthDp, crease, it) }
}

fun cardStopOpened(stop: CardStop): CardStop? = when (stop) {
    CardStop.PEEK -> CardStop.HALF
    CardStop.HALF -> CardStop.FULL
    CardStop.FULL -> null
}

fun cardStopClosed(stop: CardStop): CardStop? = when (stop) {
    CardStop.FULL -> CardStop.HALF
    CardStop.HALF -> CardStop.PEEK
    CardStop.PEEK -> null
}

// Back closes the tracking card one stop. null at Peek, or with no card, and
// Back then does what it does without one.
fun cardStopAfterBack(layout: PaneLayout): CardStop? =
    if (layout.mode == PaneMode.CARD) layout.stop?.let(::cardStopClosed) else null

// The stop is kept for the running session only, so the next one opens at Half.
fun cardStopFor(tracking: Boolean, stop: CardStop): CardStop = if (tracking) stop else CardStop.HALF

// The tracking poll, walk distance and train match all read the board's
// station and mode, so the board must not move away while a train is tracked.
fun boardPickersLocked(appState: Int): Boolean = appState == 2

sealed interface BoardPicker {
    data object Station : BoardPicker
    data class Mode(val mode: TransportMode) : BoardPicker
}

enum class PickerTap { OPEN, KEEP, ASK }

// A locked picker still takes the tap and asks to stop tracking, so the board
// never looks usable and does nothing. The shown mode is no change to ask about.
fun pickerTap(picker: BoardPicker, appState: Int, currentMode: TransportMode): PickerTap = when {
    picker is BoardPicker.Mode && picker.mode == currentMode -> PickerTap.KEEP
    boardPickersLocked(appState) -> PickerTap.ASK
    else -> PickerTap.OPEN
}

// A confirmed picker tap stops the session before the picker opens. The
// session may have ended while the dialog was up, then the picker only opens.
data class PickerPlan(val endSession: Boolean)

fun confirmedPickerTap(appState: Int): PickerPlan = PickerPlan(endSession = boardPickersLocked(appState))

// A board row is the tracked journey when it leaves at the tracked scheduled
// time and carries the same train number. Without a train number on both, the
// destination decides. Twins in one minute differ only by train number.
fun isTrackedJourney(dep: Departure, focused: FocusedDeparture): Boolean {
    if (dep.departureTimestamp != focused.departureTimestamp) return false
    val depTrain = dep.trainNumber
    val focusedTrain = focused.trainNumber
    if (depTrain != null && focusedTrain != null) return depTrain == focusedTrain
    return dep.destination == focused.destination
}

// Re-tapping the tracked row on a split board must not restart the session.
fun isAlreadyTracked(dep: Departure, appState: Int, focused: FocusedDeparture?): Boolean =
    appState == 2 && focused != null && isTrackedJourney(dep, focused)

enum class BoardTap { TRACK, KEEP, ASK }

// A board tap tracks when nothing is tracked and leaves the tracked row alone.
// Any other row would replace a running session, its alerts and its queued
// route, so the board asks first.
fun boardTap(dep: Departure, appState: Int, focused: FocusedDeparture?): BoardTap = when {
    appState != 2 || focused == null -> BoardTap.TRACK
    isTrackedJourney(dep, focused) -> BoardTap.KEEP
    else -> BoardTap.ASK
}

// A confirmed switch ends the tracked session before the asked row starts.
// The session may have ended while the dialog was up, then nothing is ended.
// null when the asked row has become the tracked one meanwhile.
data class SwitchPlan(val endDepTs: Long?)

fun confirmedSwitch(dep: Departure, appState: Int, focused: FocusedDeparture?): SwitchPlan? =
    when (boardTap(dep, appState, focused)) {
        BoardTap.TRACK -> SwitchPlan(endDepTs = null)
        BoardTap.KEEP -> null
        BoardTap.ASK -> SwitchPlan(endDepTs = focused?.departureTimestamp)
    }

// The row the board marks as tracked. Only state 2 has a session, and only a
// split window shows the board beside it.
fun trackedRowIndex(rows: List<Departure>, appState: Int, focused: FocusedDeparture?): Int? =
    rows.indexOfFirst { isAlreadyTracked(it, appState, focused) }.takeIf { it >= 0 }

// A vertical fold or hinge across the split, in dp from the split's left edge.
// A hinge that hides no pixels has start == end.
data class VerticalFold(val startDp: Float, val endDp: Float)

