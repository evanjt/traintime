package com.evanjt.traintime

import com.evanjt.traintime.data.model.TransportMode
import org.junit.Assert.assertEquals
import org.junit.Test

class LinePillTest {
    @Test
    fun `long-distance prefixes map to the long-distance fill`() {
        for (line in listOf("IC8", "IR15", "EC", "ICE", "RJX")) {
            assertEquals(LightPalette.lineLongDistance, LightPalette.linePill(line, TransportMode.TRAIN))
        }
    }

    @Test
    fun `regional prefixes map to the regional fill`() {
        for (line in listOf("S3", "RE90", "R", "SN")) {
            assertEquals(LightPalette.lineRegional, LightPalette.linePill(line, TransportMode.TRAIN))
        }
    }

    @Test
    fun `number-only lines fall back to the mode`() {
        assertEquals(LightPalette.lineBus, LightPalette.linePill("12", TransportMode.BUS))
        assertEquals(LightPalette.lineTram, LightPalette.linePill("3", TransportMode.TRAM))
        assertEquals(LightPalette.lineRegional, LightPalette.linePill("5", TransportMode.TRAIN))
    }
}
