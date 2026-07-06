package com.evanjt.traintime.core.sync

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncEchoGuardTest {
    @Test
    fun freshGuardPushes() {
        assertTrue(SyncEchoGuard<String>().shouldPush("a"))
    }

    @Test
    fun resendOfSentPayloadSkipped() {
        val guard = SyncEchoGuard<String>()
        guard.noteSent("a")
        assertFalse(guard.shouldPush("a"))
        assertTrue(guard.shouldPush("b"))
    }

    @Test
    fun receivedPayloadDoesNotEchoBack() {
        val guard = SyncEchoGuard<String>()
        guard.noteReceived("remote")
        assertFalse(guard.shouldPush("remote"))
    }

    @Test
    fun newLocalEditAfterReceivePushes() {
        val guard = SyncEchoGuard<String>()
        guard.noteReceived("remote")
        guard.noteSent("remote")
        assertTrue(guard.shouldPush("local edit"))
    }
}
