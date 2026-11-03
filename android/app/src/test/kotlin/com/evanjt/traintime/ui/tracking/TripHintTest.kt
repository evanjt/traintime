package com.evanjt.traintime.ui.tracking

import android.content.res.Configuration
import com.evanjt.traintime.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.util.Locale

// A hold turns Sound or Buzz off for every trip unless Settings already has it
// off. On for this trip only shows over Settings off, so a hold from there keeps
// it off and the tap hint must not promise a hold turns it on.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TripHintTest {
    private val holdWord = mapOf("en" to "Hold", "de" to "Halten", "fr" to "Maintenez", "it" to "Tieni premuto")

    private fun hint(language: String, override: Boolean): String {
        val config = Configuration(RuntimeEnvironment.getApplication().resources.configuration)
        config.setLocale(Locale.forLanguageTag(language))
        val context = RuntimeEnvironment.getApplication().createConfigurationContext(config)
        return context.getString(tripHint(override)!!)
    }

    @Test
    fun on_for_this_trip_never_names_the_hold() {
        holdWord.forEach { (language, hold) ->
            assertFalse("$language: ${hint(language, true)}", hint(language, true).contains(hold))
        }
    }

    @Test
    fun muted_for_this_trip_still_names_the_hold() {
        holdWord.forEach { (language, hold) ->
            assertTrue("$language: ${hint(language, false)}", hint(language, false).contains(hold))
        }
    }

    @Test
    fun landing_back_on_settings_shows_no_hint() {
        assertNull(tripHint(null))
        assertEquals(R.string.trip_muted_hint, tripHint(false))
    }
}
