package com.evanjt.traintime.ui.adaptive

import android.graphics.Rect
import androidx.window.layout.FoldingFeature
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

class PaneSplitTest {
    @Test fun noFoldKeepsTheReadableBoardWidth() {
        assertEquals(PaneSplit(boardDp = 400f, detailStartDp = 400f, onFold = false), paneSplit(widthDp = 900f, fold = null))
    }

    @Test fun aHingeAt420GivesTheBoardEverythingLeftOfIt() {
        assertEquals(PaneSplit(boardDp = 420f, detailStartDp = 420f, onFold = true), paneSplit(900f, VerticalFold(420f, 420f)))
    }

    @Test fun anOccludingFoldLeavesItsBoundsEmpty() {
        assertEquals(PaneSplit(boardDp = 400f, detailStartDp = 420f, onFold = true), paneSplit(840f, VerticalFold(400f, 420f)))
    }

    @Test fun aFoldOutsideThePaneIsIgnored() {
        assertEquals(paneSplit(900f, null), paneSplit(900f, VerticalFold(0f, 0f)))
        assertEquals(paneSplit(900f, null), paneSplit(900f, VerticalFold(900f, 920f)))
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class VerticalFoldOfTest {
    private class Fold(
        override val bounds: Rect,
        override val orientation: FoldingFeature.Orientation = FoldingFeature.Orientation.VERTICAL,
        override val isSeparating: Boolean = true,
        override val occlusionType: FoldingFeature.OcclusionType = FoldingFeature.OcclusionType.NONE,
        override val state: FoldingFeature.State = FoldingFeature.State.HALF_OPENED,
    ) : FoldingFeature

    @Test fun aSeparatingVerticalFoldIsReadInPaneDp() {
        val fold = Fold(Rect(1100, 0, 1100, 2000))
        assertEquals(VerticalFold(500f, 500f), verticalFoldOf(listOf(fold), paneLeftPx = 100f, density = 2f))
    }

    @Test fun anOccludingFoldKeepsItsWidth() {
        val fold = Fold(Rect(800, 0, 840, 2000), isSeparating = false, occlusionType = FoldingFeature.OcclusionType.FULL)
        assertEquals(VerticalFold(400f, 420f), verticalFoldOf(listOf(fold), paneLeftPx = 0f, density = 2f))
    }

    @Test fun aFlatHingeThatHidesNothingIsIgnored() {
        val fold = Fold(Rect(1000, 0, 1000, 2000), isSeparating = false, state = FoldingFeature.State.FLAT)
        assertNull(verticalFoldOf(listOf(fold), paneLeftPx = 0f, density = 2f))
    }

    @Test fun aTabletopFoldIsIgnored() {
        val fold = Fold(Rect(0, 1000, 2000, 1000), orientation = FoldingFeature.Orientation.HORIZONTAL)
        assertNull(verticalFoldOf(listOf(fold), paneLeftPx = 0f, density = 2f))
    }
}
