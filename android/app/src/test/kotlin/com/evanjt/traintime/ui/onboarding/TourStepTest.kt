package com.evanjt.traintime.ui.onboarding

import com.evanjt.traintime.data.model.TransportMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TourStepTest {
    private val trackStep = tourSteps.indexOfFirst { it.stage == TourStage.TRACK }
    private val favStep = tourSteps.indexOfFirst { it.stage == TourStage.FAVOURITE }

    @Test
    fun modeStepFollowsNearby() {
        assertEquals(TourStage.NEARBY, tourSteps[0].stage)
        assertEquals(TourStage.MODE, tourSteps[1].stage)
    }

    @Test
    fun everyModeHasItsOwnBoard() {
        val base = 1_750_000_000L
        val train = TourMockData.departures(base, TransportMode.TRAIN)
        val bus = TourMockData.departures(base, TransportMode.BUS)
        val tram = TourMockData.departures(base, TransportMode.TRAM)
        assertTrue(train.isNotEmpty() && bus.isNotEmpty() && tram.isNotEmpty())
        assertTrue(train.map { it.lineNumber }.intersect(bus.map { it.lineNumber }.toSet()).isEmpty())
        assertTrue(train.map { it.lineNumber }.intersect(tram.map { it.lineNumber }.toSet()).isEmpty())
    }

    @Test
    fun trackAndFavouriteTargetsSitOnTheTrainBoard() {
        val lines = TourMockData.departures(1_750_000_000L, TransportMode.TRAIN).map { it.lineNumber }
        assertTrue(TourMockData.TRACK_LINE in lines)
        assertTrue(TourMockData.FAVOURITE_LINE in lines)
    }

    @Test
    fun dotTotalCountsBothSubPages() {
        val (_, total) = tourDotPosition(tourSteps, 0, trackingActive = false, hasFavourites = false)
        assertEquals(tourSteps.size + 2, total)
    }

    @Test
    fun dotsAdvanceThroughBothSubPages() {
        // Straight walk: every step and sub-page yields a strictly increasing dot.
        val walk = buildList {
            for (i in tourSteps.indices) {
                add(tourDotPosition(tourSteps, i, trackingActive = false, hasFavourites = i > favStep).first)
                if (i == trackStep) add(tourDotPosition(tourSteps, i, trackingActive = true, hasFavourites = false).first)
                if (i == favStep) add(tourDotPosition(tourSteps, i, trackingActive = false, hasFavourites = true).first)
            }
        }
        assertEquals((0 until tourSteps.size + 2).toList(), walk)
    }

    // A delta tour that omits TRACK/FAVOURITE must not reserve their sub-page dots.
    @Test
    fun subsetWithoutSubPagesHasNoExtraDots() {
        val subset = listOf(tourSteps.first { it.stage == TourStage.ROUTE_PLAN })
        val (index, total) = tourDotPosition(subset, 0, trackingActive = false, hasFavourites = false)
        assertEquals(0, index)
        assertEquals(1, total)
    }

    private val v2Steps = tourSteps + TourStep(TourStage.WIDGET, "New thing", "Body", introducedIn = 2)

    @Test
    fun newInstallSeesEveryStep() {
        assertEquals(v2Steps, stepsToShow(v2Steps, effectiveSeen = 0, current = 2))
    }

    @Test
    fun updaterSeesOnlyNewerSteps() {
        val shown = stepsToShow(v2Steps, effectiveSeen = 1, current = 2)
        assertEquals(listOf(v2Steps.last()), shown)
    }

    @Test
    fun upToDateUserSeesNothing() {
        assertTrue(stepsToShow(v2Steps, effectiveSeen = 2, current = 2).isEmpty())
    }

    @Test
    fun legacyFinisherCountsAsVersionOne() {
        assertEquals(1, effectiveSeenVersion(hasSeen = true, seenVersion = 0))
        assertEquals(0, effectiveSeenVersion(hasSeen = false, seenVersion = 0))
        assertEquals(3, effectiveSeenVersion(hasSeen = true, seenVersion = 3))
    }
}
