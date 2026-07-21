package com.evanjt.traintime.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DepartureTest {
    private fun dep(minutesUntil: Int) = Departure(
        destination = "Brig",
        minutesUntil = minutesUntil,
        departureTimestamp = 1000L,
        delay = 0,
        platform = "1",
        platformChanged = false,
        lineNumber = "IC8",
        category = "IC",
        trainNumber = null,
        operatorRef = null,
    )

    @Test
    fun `minutes boundaries cover gone, now and minutes`() {
        assertTrue(dep(-1).isGone)
        assertEquals(0, dep(0).minutesUntil)
        assertEquals(5, dep(5).minutesUntil)
    }

    @Test
    fun `is gone only when negative`() {
        assertTrue(dep(-1).isGone)
        assertFalse(dep(0).isGone)
        assertFalse(dep(3).isGone)
    }

    private fun coppetDep(
        trainNumber: String?,
        delay: Int = 0,
        platform: String = "2",
        timestamp: Long = 1783171320L,
    ) = Departure(
        destination = "Coppet",
        minutesUntil = 5,
        departureTimestamp = timestamp,
        delay = delay,
        platform = platform,
        platformChanged = false,
        lineNumber = "RL4",
        category = "R",
        trainNumber = trainNumber,
        operatorRef = "11",
    )

    @Test
    fun `stable id includes train number and tolerates null`() {
        assertEquals("1783171320|RL4|Coppet|23153", coppetDep(trainNumber = "23153").stableId)
        assertEquals("1783171320|RL4|Coppet|", coppetDep(trainNumber = null).stableId)
    }

    // Scenario: OJP publishes the same train under two journey numbers
    // (RL4 → Coppet as 23153 and 93153); only one carries the live delay.
    // Expected behaviour: one row survives, the delay-bearing one,
    // regardless of input order.
    @Test
    fun `dedupe collapses twin publications keeping the delay-bearing row`() {
        val planned = coppetDep(trainNumber = "23153")
        val tracked = coppetDep(trainNumber = "93153", delay = 1)
        for (input in listOf(listOf(planned, tracked), listOf(tracked, planned))) {
            val out = input.dedupedForDisplay()
            assertEquals(1, out.size)
            assertEquals("93153", out.first().trainNumber)
            assertEquals(1, out.first().delay)
        }
    }

    @Test
    fun `dedupe keeps rows a passenger can tell apart`() {
        val quayOne = coppetDep(trainNumber = "23153", platform = "1")
        val quayTwo = coppetDep(trainNumber = "93153", platform = "2")
        val laterTrain = coppetDep(trainNumber = "23155", timestamp = 1783171380L)
        val out = listOf(quayOne, quayTwo, laterTrain).dedupedForDisplay()
        assertEquals(3, out.size)
        assertEquals(3, out.map { it.stableId }.toSet().size)
    }

    @Test
    fun `dedupe preserves first-seen order when the survivor arrives late`() {
        val earlier = coppetDep(trainNumber = "1", timestamp = 1783171000L)
        val planned = coppetDep(trainNumber = "23153")
        val later = coppetDep(trainNumber = "2", timestamp = 1783171900L)
        val tracked = coppetDep(trainNumber = "93153", delay = 1)
        val out = listOf(earlier, planned, later, tracked).dedupedForDisplay()
        assertEquals(listOf("1", "93153", "2"), out.map { it.trainNumber })
    }
}
