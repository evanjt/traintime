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
        assertTrue(msg.syncCapable)
        assertEquals("0.6.0", msg.displayVersion)
    }

    @Test
    fun bareKindStringDecodesAsLegacyWatch() {
        val msg = WearSync.decodeLiveness(WearSync.KIND_HELLO)
        assertEquals(WearSync.KIND_HELLO, msg.kind)
        assertEquals(WearSync.LEGACY_VERSION_NAME, msg.v)
        assertEquals(0, msg.pv)
        assertFalse(msg.syncCapable)
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
    fun syncMinimumRequires05OrHigher() {
        assertTrue(WearSync.meetsSyncMinimum("0.5.0"))
        assertTrue(WearSync.meetsSyncMinimum("0.5.1"))
        assertTrue(WearSync.meetsSyncMinimum("0.5.x"))
        assertTrue(WearSync.meetsSyncMinimum("0.6.0"))
        assertTrue(WearSync.meetsSyncMinimum("1.0.0"))
        assertFalse(WearSync.meetsSyncMinimum("0.4.x"))
        assertFalse(WearSync.meetsSyncMinimum("0.4.9"))
        assertFalse(WearSync.meetsSyncMinimum(null))
        assertFalse(WearSync.meetsSyncMinimum(""))
        assertFalse(WearSync.meetsSyncMinimum("garbage"))
    }
}
