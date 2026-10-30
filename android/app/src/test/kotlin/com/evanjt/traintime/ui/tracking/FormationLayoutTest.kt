package com.evanjt.traintime.ui.tracking

import com.evanjt.traintime.data.model.FormationWagon
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FormationLayoutTest {
    private fun car(number: Int, vararg features: String, closed: Boolean = false, noPassageAfter: Boolean = false) =
        FormationWagon(number, number, 2, "A", features.toList(), closed, noPassageAfter = noPassageAfter)

    @Test
    fun `sixteen cars with a break fit a narrow phone`() {
        val wagons = (1..16).map { car(it, noPassageAfter = it == 8) }
        val layout = formationLayout(wagons, 300f)
        assertTrue("width ${layout.width}", layout.width <= 300f)
        assertEquals(16, layout.carLefts.size)
        assertEquals(1, layout.barCentres.size)
        val bar = layout.barCentres.single()
        assertTrue(bar > layout.carLefts[7] + layout.carWidth && bar < layout.carLefts[8])
    }

    @Test
    fun `a short train keeps a sensible car width`() {
        val layout = formationLayout((1..3).map { car(it) }, 360f)
        assertEquals(FormationMetrics.MAX_CAR, layout.carWidth)
        assertTrue(layout.barCentres.isEmpty())
    }

    @Test
    fun `the icon lane shows one amenity by priority and nothing unknown`() {
        assertEquals("restaurant", laneFeature(car(1, "wheelchair", "restaurant", "low_floor")))
        assertEquals("bike", laneFeature(car(2, "business", "low_floor", "bike")))
        assertNull(laneFeature(car(3, "low_floor", "pram")))
        assertNull(laneFeature(car(4, "wifi")))
        assertNull(laneFeature(car(5, "restaurant", closed = true)))
    }
}
