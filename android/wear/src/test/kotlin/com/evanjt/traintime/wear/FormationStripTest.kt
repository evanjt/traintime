package com.evanjt.traintime.wear

import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FormationStripTest {
    // The strip widths on the small and large round watches, after the screen's padding
    private val widths = listOf(168f, 203f)

    // A digit or dash at the label size, a little wider than it renders so the test errs tight
    private val charWidth = 6f

    private fun labelsFor(formation: Formation, width: Float): Pair<FormationStrip, List<CarLabel>> {
        val strip = FormationStrip(width, formation.wagons.map { it.noPassageAfter })
        val labels = numberLabels(
            formation.wagons.map { it.number },
            formation.wagons.map { it.wagonClass },
            formation.wagons.map { it.noPassageAfter },
        ) { label, a, b -> strip.fits(label.length * charWidth, a, b) }
        return strip to labels
    }

    private fun assertCoversEachCarOnce(formation: Formation, labels: List<CarLabel>) {
        val breaks = formation.wagons.map { it.noPassageAfter }
        val seen = IntArray(formation.wagons.size)
        for (label in labels) {
            for (i in label.first..label.last) seen[i]++
            for (i in label.first until label.last) {
                assertFalse("label ${label.text} crosses the break after car $i", breaks[i])
            }
        }
        assertTrue("every car covered exactly once: ${seen.toList()}", seen.all { it == 1 })
    }

    @Test
    fun longTrainsGetRangesThatCoverEveryCarOnce() {
        for (formation in listOf(FormationFixtures.ic708, FormationFixtures.ic977)) {
            for (width in widths) {
                val (_, labels) = labelsFor(formation, width)
                assertCoversEachCarOnce(formation, labels)
            }
        }
        val (_, small708) = labelsFor(FormationFixtures.ic708, widths[0])
        assertTrue("16 cars on the small watch are too narrow for their own numbers", small708.any { it.last > it.first })
    }

    @Test
    fun everyCarFitsInsideTheStrip() {
        for (formation in listOf(FormationFixtures.ic708, FormationFixtures.ic977)) {
            for (width in widths) {
                val strip = FormationStrip(width, formation.wagons.map { it.noPassageAfter })
                assertEquals(formation.wagons.size, strip.cars.size)
                assertTrue(strip.cars.first().start > 0f)
                assertTrue("last car ends at ${strip.cars.last().endInclusive} of $width", strip.cars.last().endInclusive <= width + 0.01f)
                assertTrue(strip.carWidth > 4f)
            }
        }
    }

    @Test
    fun theBreakGetsAWiderGapThanTheOthers() {
        val strip = FormationStrip(168f, FormationFixtures.ic708.wagons.map { it.noPassageAfter })
        val gapAfter = { i: Int -> strip.cars[i + 1].start - strip.cars[i].endInclusive }
        assertTrue(gapAfter(7) > gapAfter(6))
        assertEquals(gapAfter(6), gapAfter(8), 0.001f)
    }

    @Test
    fun aShortTrainNumbersEveryCar() {
        val numbers = listOf(9, 8, 7, 6, 5, 4, 3, 2, 1)
        val strip = FormationStrip(168f, List(9) { false })
        val labels = numberLabels(numbers, listOf(2, 2, 2, 2, 2, 2, 1, 1, 1), List(9) { false }) { label, a, b ->
            strip.fits(label.length * charWidth, a, b)
        }
        assertEquals(numbers.indices.map { CarLabel(it, it, numbers[it].toString()) }, labels)
    }

    @Test
    fun aTrainWithNoNumberedCarShowsNoNumbers() {
        val labels = numberLabels(List(6) { null }, listOf(2, 2, 1, 2, 2, 2), List(6) { false }) { _, _, _ -> true }
        assertEquals(emptyList<CarLabel>(), labels)
    }

    @Test
    fun onlyTheNumberedCarsAreLabelled() {
        val numbers = listOf(null, 9, 8, null, 2, 1)
        val classes = listOf(2, 2, 2, 2, 1, 1)
        val roomy = numberLabels(numbers, classes, List(6) { false }) { _, _, _ -> true }
        assertEquals(listOf(CarLabel(1, 1, "9"), CarLabel(2, 2, "8"), CarLabel(4, 4, "2"), CarLabel(5, 5, "1")), roomy)
        // Too narrow for single numbers: ranges run over numbered cars only, never across an unnumbered one
        val tight = numberLabels(numbers, classes, List(6) { false }) { _, a, b -> b > a }
        assertEquals(listOf(CarLabel(1, 2, "9-8"), CarLabel(4, 5, "2-1")), tight)
    }

    @Test
    fun aTailThatDoesNotFitJoinsTheLabelBefore() {
        // Cars wide enough for a three-car range but not a two-car one
        val labels = numberLabels(listOf(18, 17, 16, 15, 14), listOf(2, 2, 2, 1, 1), List(5) { false }) { _, a, b ->
            b - a >= 2
        }
        assertEquals(listOf(CarLabel(0, 4, "18-14")), labels)
    }

    @Test
    fun theStepCursorWrapsAndStartsFromTheEndItEntersBy() {
        assertEquals(0, stepCar(null, 1, 12))
        assertEquals(11, stepCar(null, -1, 12))
        assertEquals(0, stepCar(11, 1, 12))
        assertEquals(11, stepCar(0, -1, 12))
        assertEquals(5, stepCar(4, 1, 12))
    }

    @Test
    fun theReadoutRingDrainsOverFiveSeconds() {
        assertEquals(1f, readoutLeft(0L), 0.001f)
        assertEquals(0.5f, readoutLeft(2_500L), 0.001f)
        assertEquals(0f, readoutLeft(5_000L), 0.001f)
        assertEquals(0f, readoutLeft(9_000L), 0.001f)
    }

    @Test
    fun amenitiesKeepTheirOrderAndDropTheRest() {
        assertEquals(
            listOf(Amenity.RESTAURANT, Amenity.WHEELCHAIR, Amenity.BIKE),
            amenities(listOf("bike", "low_floor", "wheelchair", "business", "restaurant")),
        )
        assertEquals(emptyList<Amenity>(), amenities(listOf("kw")))
    }

    @Test
    fun aClosedCarCarriesNoNumberAndNoAmenities() {
        val open = FormationWagon(1, 7, 2, "C", listOf("bike"), false)
        val closed = FormationWagon(2, 8, 1, "D", listOf("restaurant", "wheelchair"), true)
        assertEquals(listOf(7, null), labelNumbers(listOf(open, closed)))
        assertEquals(listOf(Amenity.BIKE), carAmenities(open))
        assertEquals(emptyList<Amenity>(), carAmenities(closed))
    }
}
