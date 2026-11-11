package com.evanjt.traintime.ui.adaptive

import android.graphics.Rect
import androidx.window.layout.FoldingFeature
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

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
