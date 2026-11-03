package com.evanjt.traintime.domain

import android.os.VibrationEffect
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HapticServiceTest {
    private val sent = mutableListOf<VibrationEffect>()

    private fun buzzEverything(service: HapticService) {
        service.shortPulse()
        service.doublePulse()
        service.heartbeat()
        service.platformChange()
    }

    @Test
    fun `vibration off sends nothing to the vibrator`() {
        buzzEverything(HapticService(sink = { sent += it }, enabled = { false }))
        assertEquals(0, sent.size)
    }

    @Test
    fun `vibration on sends every pattern`() {
        buzzEverything(HapticService(sink = { sent += it }, enabled = { true }))
        assertEquals(4, sent.size)
    }

    @Test
    fun `the flag is read at each buzz`() {
        var on = true
        val service = HapticService(sink = { sent += it }, enabled = { on })
        service.shortPulse()
        on = false
        service.shortPulse()
        assertEquals(1, sent.size)
    }
}
