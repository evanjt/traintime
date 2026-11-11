package com.evanjt.traintime.ui.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CardStopTest {
    @Test fun openingMovesTheCardOneStopTowardFull() {
        assertEquals(CardStop.HALF, cardStopOpened(CardStop.PEEK))
        assertEquals(CardStop.FULL, cardStopOpened(CardStop.HALF))
        assertNull(cardStopOpened(CardStop.FULL))
    }

    @Test fun closingMovesTheCardOneStopTowardPeek() {
        assertEquals(CardStop.HALF, cardStopClosed(CardStop.FULL))
        assertEquals(CardStop.PEEK, cardStopClosed(CardStop.HALF))
        assertNull(cardStopClosed(CardStop.PEEK))
    }

    @Test fun backClosesTheTrackingCardOneStopAtATime() {
        val full = paneLayout(674f, 841f, null, appState = 2, stop = CardStop.FULL)
        assertEquals(CardStop.HALF, cardStopAfterBack(full))
        val half = paneLayout(674f, 841f, null, appState = 2, stop = CardStop.HALF)
        assertEquals(CardStop.PEEK, cardStopAfterBack(half))
    }

    @Test fun backAtPeekOrWithoutACardDoesWhatItDidBefore() {
        assertNull(cardStopAfterBack(paneLayout(674f, 841f, null, appState = 2, stop = CardStop.PEEK)))
        assertNull(cardStopAfterBack(paneLayout(674f, 841f, null, appState = 0, stop = CardStop.FULL)))
        assertNull(cardStopAfterBack(paneLayout(951f, 669f, null, appState = 2, stop = CardStop.FULL)))
        assertNull(cardStopAfterBack(paneLayout(393f, 852f, null, appState = 2, stop = CardStop.FULL)))
    }

    @Test fun aSessionEndingForgetsItsStopSoTheNextOneOpensAtHalf() {
        assertEquals(CardStop.HALF, cardStopFor(tracking = false, stop = CardStop.FULL))
        assertEquals(CardStop.HALF, cardStopFor(tracking = false, stop = CardStop.PEEK))
        assertEquals(CardStop.FULL, cardStopFor(tracking = true, stop = CardStop.FULL))
    }

    @Test fun theCardEdgeRestsAtOneAnchorPerStop() {
        assertEquals(
            mapOf(CardStop.PEEK to 466f, CardStop.HALF to 314f, CardStop.FULL to 0f),
            cardEdges(674f, null),
        )
    }

    @Test fun anAnchorNeverSitsInsideAnOccludedStrip() {
        assertEquals(300f, cardEdges(674f, VerticalFold(300f, 330f))[CardStop.HALF])
    }
}
