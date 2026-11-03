package com.evanjt.traintime.ui.adaptive

import org.junit.Assert.assertEquals
import org.junit.Test

class PaneLayoutTest {
    @Test fun widthClassFollowsMaterialBreakpoints() {
        assertEquals(WidthClass.COMPACT, widthClassOf(411f))
        assertEquals(WidthClass.COMPACT, widthClassOf(599.9f))
        assertEquals(WidthClass.MEDIUM, widthClassOf(600f))
        assertEquals(WidthClass.MEDIUM, widthClassOf(839.9f))
        assertEquals(WidthClass.EXPANDED, widthClassOf(840f))
        assertEquals(WidthClass.EXPANDED, widthClassOf(1280f))
    }

    @Test fun expandedTrackingSplitsBoardAndTracking() {
        assertEquals(PaneLayout.SPLIT_TRACKING, paneLayout(WidthClass.EXPANDED, appState = 2))
    }

    @Test fun expandedIdleSplitsBoardAndHint() {
        assertEquals(PaneLayout.SPLIT_HINT, paneLayout(WidthClass.EXPANDED, appState = 0))
        assertEquals(PaneLayout.SPLIT_HINT, paneLayout(WidthClass.EXPANDED, appState = 3))
    }

    @Test fun compactAndMediumKeepTheSingleScreenFlow() {
        for (width in listOf(WidthClass.COMPACT, WidthClass.MEDIUM)) {
            assertEquals(PaneLayout.TRACKING, paneLayout(width, appState = 2))
            assertEquals(PaneLayout.BOARD, paneLayout(width, appState = 0))
            assertEquals(PaneLayout.BOARD, paneLayout(width, appState = 3))
        }
    }
}
