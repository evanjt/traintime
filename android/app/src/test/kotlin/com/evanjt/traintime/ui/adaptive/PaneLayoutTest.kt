package com.evanjt.traintime.ui.adaptive

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.TransportMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaneLayoutTest {
    private fun layout(w: Float, h: Float, appState: Int, fold: VerticalFold? = null, stop: CardStop? = null) =
        paneLayout(widthDp = w, heightDp = h, fold = fold, appState = appState, stop = stop)

    private val bookCrease = VerticalFold(337f, 337f)

    @Test fun aCompactPhoneShowsTheBoardThenTrackingFullScreen() {
        assertEquals(PaneMode.BOARD, layout(393f, 852f, appState = 0).mode)
        assertEquals(PaneMode.BOARD, layout(393f, 852f, appState = 3).mode)
        assertEquals(PaneMode.TRACKING, layout(393f, 852f, appState = 2).mode)
    }

    @Test fun aCompactHeightWindowNeverSplitsOrShowsTheCard() {
        for ((w, h) in listOf(678f to 466f, 956f to 440f)) {
            assertEquals(PaneMode.BOARD, layout(w, h, appState = 0).mode)
            assertEquals(PaneMode.TRACKING, layout(w, h, appState = 2).mode)
        }
    }

    @Test fun twoPhoneWidthPanesSitSideBySideSplitAtTheMiddle() {
        for (appState in listOf(0, 2)) {
            val duo = layout(951f, 669f, appState)
            assertEquals(PaneMode.SIDE_BY_SIDE, duo.mode)
            assertEquals(475f, duo.boardDp)
            assertEquals(475f, 951f - duo.detailStartDp)
        }
        val tablet = layout(1280f, 800f, appState = 2)
        assertEquals(PaneMode.SIDE_BY_SIDE, tablet.mode)
        assertTrue(tablet.boardDp >= BOARD_WIDTH_DP && 1280f - tablet.detailStartDp >= BOARD_WIDTH_DP)
    }

    @Test fun sideBySideSplitsOnAReportedFold() {
        val split = layout(1280f, 800f, appState = 2, fold = VerticalFold(630f, 650f))
        assertEquals(PaneLayout(PaneMode.SIDE_BY_SIDE, null, 630f, 650f, onFold = true), split)
    }

    @Test fun aNarrowerWideWindowRestsTheCardAtPeekWhileIdle() {
        for ((w, h) in listOf(669f to 951f, 674f to 841f)) {
            for (fold in listOf(null, bookCrease)) {
                for (appState in listOf(0, 3)) {
                    val peek = layout(w, h, appState, fold, stop = CardStop.HALF)
                    assertEquals(PaneMode.CARD, peek.mode)
                    assertEquals(CardStop.PEEK, peek.stop)
                    assertTrue(peek.boardDp >= BOARD_WIDTH_DP && peek.boardDp <= 466f)
                    assertTrue(w - peek.detailStartDp >= 200f)
                }
            }
        }
    }

    @Test fun startingTrackingOpensTheCardAtHalf() {
        for ((w, h) in listOf(669f to 951f, 674f to 841f)) {
            for (fold in listOf(null, bookCrease)) {
                val half = layout(w, h, appState = 2, fold = fold)
                assertEquals(PaneMode.CARD, half.mode)
                assertEquals(CardStop.HALF, half.stop)
                assertTrue(w - half.detailStartDp >= 360f)
                assertEquals(half.detailStartDp, half.boardDp)
            }
        }
    }

    @Test fun theDuoTurnedKeepsTheBoardReadableAtPeek() {
        assertEquals(466f, layout(669f, 951f, appState = 0).boardDp)
    }

    @Test fun theCardTakesTheWholeWindowAtFull() {
        val full = layout(674f, 841f, appState = 2, stop = CardStop.FULL)
        assertEquals(PaneLayout(PaneMode.CARD, CardStop.FULL, 0f, 0f, onFold = false), full)
    }

    @Test fun aCardEdgeNeverRestsInsideAnOccludedStrip() {
        val strip = VerticalFold(300f, 330f)
        val half = layout(674f, 841f, appState = 2, fold = strip)
        assertEquals(300f, half.detailStartDp)
        val peekStrip = VerticalFold(460f, 480f)
        assertEquals(460f, layout(674f, 841f, appState = 0, fold = peekStrip).detailStartDp)
    }

    @Test fun boardPickersLockOnlyWhileTracking() {
        assertTrue(boardPickersLocked(appState = 2))
        assertFalse(boardPickersLocked(appState = 0))
        assertFalse(boardPickersLocked(appState = 3))
    }

    @Test fun aPickerTapWhileTrackingAsksToStop() {
        assertEquals(PickerTap.ASK, pickerTap(BoardPicker.Station, appState = 2, currentMode = TransportMode.TRAIN))
        assertEquals(PickerTap.ASK, pickerTap(BoardPicker.Mode(TransportMode.BUS), appState = 2, currentMode = TransportMode.TRAIN))
    }

    @Test fun aPickerTapWhenIdleOpens() {
        for (appState in listOf(0, 3)) {
            assertEquals(PickerTap.OPEN, pickerTap(BoardPicker.Station, appState, currentMode = TransportMode.TRAIN))
            assertEquals(PickerTap.OPEN, pickerTap(BoardPicker.Mode(TransportMode.BUS), appState, currentMode = TransportMode.TRAIN))
        }
    }

    @Test fun aTapOnTheShownModeChangesNothing() {
        for (appState in listOf(0, 2)) {
            assertEquals(PickerTap.KEEP, pickerTap(BoardPicker.Mode(TransportMode.TRAIN), appState, currentMode = TransportMode.TRAIN))
        }
    }

    @Test fun aConfirmedPickerTapEndsTheSessionBeforeThePickerOpens() {
        assertEquals(PickerPlan(endSession = true), confirmedPickerTap(appState = 2))
    }

    @Test fun aPickerTapConfirmedAfterTheSessionEndedOnlyOpens() {
        assertEquals(PickerPlan(endSession = false), confirmedPickerTap(appState = 0))
    }

    private val tracked = FocusedDeparture(
        destination = "Lakeside",
        departureTimestamp = 1_800_000_000L,
        lineNumber = "S9",
        category = "S",
        trainNumber = null,
        operatorRef = null,
        delay = 0,
        platform = "4",
        platformChanged = false,
    )

    private fun row(dest: String, ts: Long, train: String?) = Departure(
        destination = dest,
        minutesUntil = 5,
        departureTimestamp = ts,
        delay = 0,
        platform = "4",
        platformChanged = false,
        lineNumber = "S9",
        category = "S",
        trainNumber = train,
        operatorRef = null,
    )

    @Test fun theTrackedRowIsAlreadyTracked() {
        assertTrue(isAlreadyTracked(row("Lakeside", 1_800_000_000L, null), appState = 2, focused = tracked))
    }

    @Test fun anotherRowOrNoSessionIsNotAlreadyTracked() {
        assertFalse(isAlreadyTracked(row("Lakeside", 1_800_000_600L, null), appState = 2, focused = tracked))
        assertFalse(isAlreadyTracked(row("Hilltop", 1_800_000_000L, null), appState = 2, focused = tracked))
        assertFalse(isAlreadyTracked(row("Lakeside", 1_800_000_000L, null), appState = 0, focused = tracked))
        assertFalse(isAlreadyTracked(row("Lakeside", 1_800_000_000L, null), appState = 2, focused = null))
    }

    private val trackedTrain = tracked.copy(trainNumber = "18234")

    @Test fun aBoardTapTracksWhenNothingIsTracked() {
        val dep = row("Hilltop", 1_800_000_600L, "18236")
        assertEquals(BoardTap.TRACK, boardTap(dep, appState = 0, focused = null))
        assertEquals(BoardTap.TRACK, boardTap(dep, appState = 3, focused = trackedTrain))
    }

    @Test fun aBoardTapOnTheTrackedRowKeepsTheSession() {
        assertEquals(BoardTap.KEEP, boardTap(row("Lakeside", 1_800_000_000L, "18234"), appState = 2, focused = trackedTrain))
    }

    @Test fun aBoardTapOnATwinOfTheTrackedTrainAsks() {
        assertEquals(BoardTap.ASK, boardTap(row("Lakeside", 1_800_000_000L, "98234"), appState = 2, focused = trackedTrain))
    }

    @Test fun aBoardTapOnAnotherRowAsks() {
        assertEquals(BoardTap.ASK, boardTap(row("Lakeside", 1_800_000_600L, "18236"), appState = 2, focused = trackedTrain))
    }

    @Test fun aConfirmedSwitchEndsTheTrackedSessionFirst() {
        val plan = confirmedSwitch(row("Lakeside", 1_800_000_600L, "18236"), appState = 2, focused = trackedTrain)
        assertEquals(SwitchPlan(endDepTs = 1_800_000_000L), plan)
    }

    @Test fun aSwitchConfirmedAfterTheSessionEndedOnlyTracks() {
        val plan = confirmedSwitch(row("Lakeside", 1_800_000_600L, "18236"), appState = 0, focused = null)
        assertEquals(SwitchPlan(endDepTs = null), plan)
    }

    @Test fun aSwitchToTheNowTrackedRowDoesNothing() {
        assertEquals(null, confirmedSwitch(row("Lakeside", 1_800_000_000L, "18234"), appState = 2, focused = trackedTrain))
    }

    @Test fun theTrackedRowIsMarkedWhileTracking() {
        val rows = listOf(
            row("Hilltop", 1_800_000_000L, "18111"),
            row("Lakeside", 1_800_000_000L, "18234"),
            row("Lakeside", 1_800_000_600L, "18236"),
        )
        assertEquals(1, trackedRowIndex(rows, appState = 2, focused = trackedTrain))
    }

    // Two journeys on the same line at the same minute to the same place differ
    // only by train number, so only the tracked one is marked.
    @Test fun aTwinOfAnotherJourneyIsNotMarked() {
        val rows = listOf(
            row("Lakeside", 1_800_000_000L, "98234"),
            row("Lakeside", 1_800_000_000L, "18234"),
        )
        assertEquals(1, trackedRowIndex(rows, appState = 2, focused = trackedTrain))
        assertFalse(isAlreadyTracked(rows[0], appState = 2, focused = trackedTrain))
        assertTrue(isAlreadyTracked(rows[1], appState = 2, focused = trackedTrain))
    }

    @Test fun withoutATrainNumberTheDestinationIdentifiesTheRow() {
        val rows = listOf(row("Hilltop", 1_800_000_000L, null), row("Lakeside", 1_800_000_000L, null))
        assertEquals(1, trackedRowIndex(rows, appState = 2, focused = tracked))
    }

    @Test fun nothingIsMarkedWithoutASessionOrAMatch() {
        val rows = listOf(row("Lakeside", 1_800_000_000L, "18234"))
        assertEquals(null, trackedRowIndex(rows, appState = 0, focused = trackedTrain))
        assertEquals(null, trackedRowIndex(rows, appState = 3, focused = trackedTrain))
        assertEquals(null, trackedRowIndex(rows, appState = 2, focused = null))
        assertEquals(null, trackedRowIndex(listOf(row("Lakeside", 1_800_000_600L, "18236")), appState = 2, focused = trackedTrain))
    }
}
