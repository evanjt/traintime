package com.evanjt.traintime.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminTipTest {
    private fun show(
        garminConnectInstalled: Boolean = true,
        everLinked: Boolean = false,
        seen: Boolean = false,
        tourDone: Boolean = true,
        launches: Int = GarminTipGate.MIN_LAUNCHES,
    ) = GarminTipGate.shouldShow(garminConnectInstalled, everLinked, seen, tourDone, launches)

    @Test
    fun `garmin connect on the phone and never linked shows the tip`() {
        assertTrue(show())
    }

    @Test
    fun `no garmin connect never shows`() {
        assertFalse(show(garminConnectInstalled = false))
    }

    @Test
    fun `a garmin that has ever linked never shows`() {
        assertFalse(show(everLinked = true))
    }

    @Test
    fun `seen once never shows again`() {
        assertFalse(show(seen = true))
    }

    @Test
    fun `waits until the onboarding tour is done`() {
        assertFalse(show(tourDone = false))
    }

    @Test
    fun `waits for a few launches`() {
        assertFalse(show(launches = GarminTipGate.MIN_LAUNCHES - 1))
    }

    @Test
    fun `store url follows the app language`() {
        val id = ConnectIqStore.APP_ID
        assertEquals("https://apps.garmin.com/de-DE/apps/$id", ConnectIqStore.url("de"))
        assertEquals("https://apps.garmin.com/fr-FR/apps/$id", ConnectIqStore.url("fr-CH"))
        assertEquals("https://apps.garmin.com/it-IT/apps/$id", ConnectIqStore.url("it"))
        assertEquals("https://apps.garmin.com/en-US/apps/$id", ConnectIqStore.url("en"))
        assertEquals("https://apps.garmin.com/en-US/apps/$id", ConnectIqStore.url("rm"))
    }
}
