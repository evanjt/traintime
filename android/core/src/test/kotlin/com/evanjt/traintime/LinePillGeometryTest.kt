package com.evanjt.traintime

import org.junit.Assert.assertEquals
import org.junit.Test

class LinePillGeometryTest {
    @Test
    fun `labels up to five characters keep the chip font`() {
        for (label in listOf("", "S3", "16", "BEG", "IR95", "V41", "RE33X")) {
            assertEquals(1f, LinePillGeometry.fontScale(label), 0f)
        }
    }

    @Test
    fun `a longer label shrinks in proportion so it fits the five-character width`() {
        assertEquals(5f / 6f, LinePillGeometry.fontScale("ICE123"), 1e-6f)
        assertEquals(0.5f, LinePillGeometry.fontScale("ABCDEFGHIJ"), 1e-6f)
    }
}
