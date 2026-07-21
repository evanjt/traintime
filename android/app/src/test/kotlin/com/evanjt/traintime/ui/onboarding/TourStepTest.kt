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

    // Synthetic future step one version past the real tour, so it is always the
    // sole newest step regardless of what CURRENT_TOUR_VERSION introduces.
    private val nextVersion = CURRENT_TOUR_VERSION + 1
    private val futureStep = TourStep(TourStage.WIDGET, "New thing", "Body", introducedIn = nextVersion)
    private val futureSteps = tourSteps + futureStep

    @Test
    fun newInstallSeesEveryStep() {
        assertEquals(futureSteps, stepsToShow(futureSteps, effectiveSeen = 0, current = nextVersion))
    }

    @Test
    fun updaterSeesOnlyNewerSteps() {
        val shown = stepsToShow(futureSteps, effectiveSeen = CURRENT_TOUR_VERSION, current = nextVersion)
        assertEquals(listOf(futureStep), shown)
    }

    @Test
    fun upToDateUserSeesNothing() {
        assertTrue(stepsToShow(futureSteps, effectiveSeen = nextVersion, current = nextVersion).isEmpty())
    }

    // v2 re-introduced the watch step (Wear OS released), so a v1 finisher sees it once.
    @Test
    fun v1FinisherSeesTheWatchAnnouncement() {
        val shown = stepsToShow(tourSteps, effectiveSeen = 1, current = CURRENT_TOUR_VERSION)
        assertEquals(listOf(TourStage.WATCH), shown.map { it.stage })
    }

    @Test
    fun legacyFinisherCountsAsVersionOne() {
        assertEquals(1, effectiveSeenVersion(hasSeen = true, seenVersion = 0))
        assertEquals(0, effectiveSeenVersion(hasSeen = false, seenVersion = 0))
        assertEquals(3, effectiveSeenVersion(hasSeen = true, seenVersion = 3))
    }
}
