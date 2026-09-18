package com.evanjt.traintime.data.api

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HostFailoverTest {
    private var now = 1_000L
    private val failover = HostFailover(hostCount = 3, reprobeSeconds = 300, clock = { now })

    @Test
    fun `starts on the primary`() {
        assertEquals(listOf(0, 1, 2), failover.order())
    }

    @Test
    fun `primary failure moves the preference to the next host`() {
        failover.recordFailure(0)
        assertEquals(listOf(1, 2, 0), failover.order())
    }

    @Test
    fun `failure of a host that is not preferred changes nothing`() {
        failover.recordFailure(1)
        assertEquals(listOf(0, 1, 2), failover.order())
    }

    @Test
    fun `success on a later host makes it preferred`() {
        failover.recordFailure(0)
        failover.recordFailure(1)
        failover.recordSuccess(2)
        assertEquals(listOf(2, 0, 1), failover.order())
    }

    @Test
    fun `preference is sticky until the reprobe window passes`() {
        failover.recordFailure(0)
        now += 299
        assertEquals(listOf(1, 2, 0), failover.order())
        now += 1
        assertEquals(listOf(0, 1, 2), failover.order())
    }

    @Test
    fun `reprobe window restarts from the latest demotion`() {
        failover.recordFailure(0)
        now += 200
        failover.recordFailure(1)
        now += 200
        assertEquals(listOf(2, 0, 1), failover.order())
    }

    @Test
    fun `retries on 429 and server errors only`() {
        assertTrue(HostFailover.shouldFailover(429))
        assertTrue(HostFailover.shouldFailover(500))
        assertTrue(HostFailover.shouldFailover(503))
        assertFalse(HostFailover.shouldFailover(400))
        assertFalse(HostFailover.shouldFailover(401))
        assertFalse(HostFailover.shouldFailover(404))
    }
}
