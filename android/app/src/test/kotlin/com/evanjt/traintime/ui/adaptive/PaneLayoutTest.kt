package com.evanjt.traintime.ui.adaptive

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaneLayoutTest {
    private val tall = WindowShape(widthDp = 700f, heightDp = 1000f, hasFold = false)
    private val wide = WindowShape(widthDp = 800f, heightDp = 640f, hasFold = false)
    private val unfoldedBook = WindowShape(widthDp = 674f, heightDp = 841f, hasFold = true)

    @Test fun widthClassFollowsMaterialBreakpoints() {
        assertEquals(WidthClass.COMPACT, widthClassOf(411f))
        assertEquals(WidthClass.COMPACT, widthClassOf(599.9f))
        assertEquals(WidthClass.MEDIUM, widthClassOf(600f))
        assertEquals(WidthClass.MEDIUM, widthClassOf(839.9f))
        assertEquals(WidthClass.EXPANDED, widthClassOf(840f))
        assertEquals(WidthClass.EXPANDED, widthClassOf(1280f))
    }

    @Test fun expandedTrackingSplitsBoardAndTracking() {
        val shape = WindowShape(widthDp = 900f, heightDp = 1200f, hasFold = false)
        assertEquals(PaneLayout.SPLIT_TRACKING, paneLayout(shape, appState = 2))
    }

    @Test fun expandedIdleSplitsBoardAndHint() {
        val shape = WindowShape(widthDp = 1280f, heightDp = 800f, hasFold = false)
        assertEquals(PaneLayout.SPLIT_HINT, paneLayout(shape, appState = 0))
        assertEquals(PaneLayout.SPLIT_HINT, paneLayout(shape, appState = 3))
    }

    @Test fun mediumLandscapeWindowSplits() {
        assertEquals(PaneLayout.SPLIT_TRACKING, paneLayout(wide, appState = 2))
        assertEquals(PaneLayout.SPLIT_HINT, paneLayout(wide, appState = 0))
    }

    @Test fun mediumSquareWindowSplits() {
        val square = WindowShape(widthDp = 720f, heightDp = 720f, hasFold = false)
        assertEquals(PaneLayout.SPLIT_TRACKING, paneLayout(square, appState = 2))
    }

    @Test fun mediumPortraitWindowWithAFoldSplits() {
        assertEquals(PaneLayout.SPLIT_TRACKING, paneLayout(unfoldedBook, appState = 2))
        assertEquals(PaneLayout.SPLIT_HINT, paneLayout(unfoldedBook, appState = 3))
    }

    @Test fun mediumPortraitWindowWithoutAFoldKeepsTheSingleScreenFlow() {
        assertEquals(PaneLayout.TRACKING, paneLayout(tall, appState = 2))
        assertEquals(PaneLayout.BOARD, paneLayout(tall, appState = 0))
        assertEquals(PaneLayout.BOARD, paneLayout(tall, appState = 3))
    }

    @Test fun compactKeepsTheSingleScreenFlowEvenWithAFold() {
        val folded = WindowShape(widthDp = 360f, heightDp = 879f, hasFold = true)
        val compactLandscape = WindowShape(widthDp = 590f, heightDp = 360f, hasFold = false)
        for (shape in listOf(folded, compactLandscape)) {
            assertEquals(PaneLayout.TRACKING, paneLayout(shape, appState = 2))
            assertEquals(PaneLayout.BOARD, paneLayout(shape, appState = 0))
        }
    }

    @Test fun boardPickersLockOnlyWhileTracking() {
        assertTrue(boardPickersLocked(appState = 2))
        assertFalse(boardPickersLocked(appState = 0))
        assertFalse(boardPickersLocked(appState = 3))
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
