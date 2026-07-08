package com.evanjt.traintime.core.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminPingGateTest {
    private val now = 1_718_000_000_000L

    @Test
    fun pingsRecentAliveAfterByeOnPv2() {
        assertTrue(WearSync.shouldPingGarmin(now - 5_000, now - 60_000, now, 2))
    }

    @Test
    fun refusesOldProtocol() {
        assertFalse(WearSync.shouldPingGarmin(now - 5_000, 0L, now, 1))
        assertFalse(WearSync.shouldPingGarmin(now - 5_000, 0L, now, 0))
    }

    @Test
    fun refusesAfterBye() {
        assertFalse(WearSync.shouldPingGarmin(now - 10_000, now - 5_000, now, 2))
    }

    @Test
    fun refusesStaleAlive() {
        assertFalse(WearSync.shouldPingGarmin(now - 31_000, 0L, now, 2))
        assertTrue(WearSync.shouldPingGarmin(now - 30_000, 0L, now, 2))
    }

    @Test
    fun refusesNeverHeard() {
        assertFalse(WearSync.shouldPingGarmin(0L, 0L, now, 2))
    }

    @Test
    fun ackPayloadCarriesActionAndId() {
        val payload = WearSync.garminAckReminderPayload("8507000|1718000600|IC1")
        assertEquals("ackReminder", payload["action"])
        assertEquals("8507000|1718000600|IC1", payload["id"])
    }

    @Test
    fun pingPayloadIsBareAction() {
        val payload = WearSync.garminPingPayload()
        assertEquals("ping", payload["action"])
        assertEquals(1, payload.size)
    }
}
