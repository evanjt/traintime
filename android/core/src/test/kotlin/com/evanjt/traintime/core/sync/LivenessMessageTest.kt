package com.evanjt.traintime.core.sync

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LivenessMessageTest {
    @After
    fun resetVersion() {
        WearSync.localVersionName = WearSync.LEGACY_VERSION_NAME
    }

    @Test
    fun encodeStampsLocalVersionAndProtocol() {
        WearSync.localVersionName = "0.6.0"
        val msg = WearSync.decodeLiveness(WearSync.encodeLiveness(WearSync.KIND_HELLO))
        assertEquals(WearSync.KIND_HELLO, msg.kind)
        assertEquals("0.6.0", msg.v)
        assertEquals(WearSync.PROTOCOL_VERSION, msg.pv)
        assertFalse(msg.trackOutdated)
        assertEquals("0.6.0", msg.displayVersion)
    }

    @Test
    fun bareKindStringDecodesAsLegacyWatch() {
        val msg = WearSync.decodeLiveness(WearSync.KIND_HELLO)
        assertEquals(WearSync.KIND_HELLO, msg.kind)
        assertEquals(WearSync.LEGACY_VERSION_NAME, msg.v)
        assertEquals(0, msg.pv)
        assertTrue(msg.trackOutdated)
        assertEquals(WearSync.LEGACY_VERSION_NAME, msg.displayVersion)
    }

    @Test
    fun reqLocRoundTripsWithVersion() {
        WearSync.localVersionName = "0.6.1"
        val msg = WearSync.decodeLiveness(WearSync.encodeLiveness(WearSync.KIND_REQ_LOC))
        assertEquals(WearSync.KIND_REQ_LOC, msg.kind)
        assertEquals("0.6.1", msg.displayVersion)
    }

    @Test
    fun currentProtocolIsNotOutdated() {
        val current = LivenessMessage(WearSync.KIND_ALIVE, "0.6.0", WearSync.PROTOCOL_VERSION)
        assertFalse(current.trackOutdated)
    }
}
