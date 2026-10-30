package com.evanjt.traintime.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

class SessionGateTest {
    @Test
    fun `outputs run while the session is live`() {
        val gate = SessionGate()
        assertEquals(1, gate.open { 1 })
        assertFalse(gate.isClosed)
    }

    @Test
    fun `no output runs after close`() {
        val gate = SessionGate()
        var posted = false
        gate.close {}
        assertNull(gate.open { posted = true })
        assertFalse(posted)
        assertTrue(gate.isClosed)
    }

    @Test
    fun `every close runs its teardown`() {
        val gate = SessionGate()
        var cleared = 0
        gate.close { cleared++ }
        gate.close { cleared++ }
        assertEquals(2, cleared)
    }

    // Scenario: posts from worker threads race a teardown on another thread.
    // Expected behaviour: the teardown is the last event, whatever the timing.
    @Test
    fun `a racing post never lands after close`() {
        repeat(200) {
            val gate = SessionGate()
            val events = Collections.synchronizedList(mutableListOf<String>())
            val go = CountDownLatch(1)
            val posters = List(4) {
                thread {
                    go.await()
                    repeat(50) { gate.open { events.add("post") } }
                }
            }
            go.countDown()
            gate.close { events.add("close") }
            posters.forEach { it.join() }
            assertEquals("close", events.last())
        }
    }
}
