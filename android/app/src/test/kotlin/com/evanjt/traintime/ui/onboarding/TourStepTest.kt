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
        val (_, total) = tourDotPosition(0, trackingActive = false, hasFavourites = false)
        assertEquals(tourSteps.size + 2, total)
    }

    @Test
    fun dotsAdvanceThroughBothSubPages() {
        // Straight walk: every step and sub-page yields a strictly increasing dot.
        val walk = buildList {
            for (i in tourSteps.indices) {
                add(tourDotPosition(i, trackingActive = false, hasFavourites = i > favStep).first)
                if (i == trackStep) add(tourDotPosition(i, trackingActive = true, hasFavourites = false).first)
                if (i == favStep) add(tourDotPosition(i, trackingActive = false, hasFavourites = true).first)
            }
        }
        assertEquals((0 until tourSteps.size + 2).toList(), walk)
    }
}
