package com.evanjt.traintime.ui.settings

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.evanjt.traintime.DataCredits
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AttributionContentTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val opened = mutableListOf<String>()

    private fun show(language: String) {
        composeRule.setContent {
            MaterialTheme(colorScheme = lightColorScheme()) {
                AttributionContent(language = language, open = { opened += it })
            }
        }
    }

    @Test
    fun victoriaCreditShowsLicenceLineAndLinksToLicence() {
        show("en")
        composeRule.onNodeWithText("VICTORIA, AUSTRALIA").assertExists()
        composeRule.onNodeWithText(
            "Source: Licensed from Public Transport Victoria under a Creative Commons Attribution 4.0 International Licence.",
        ).assertExists()
        composeRule.onNodeWithText(DataCredits.CC_BY_4_NAME).assertHasClickAction().performScrollTo().performClick()
        assertEquals(listOf("https://creativecommons.org/licenses/by/4.0/"), opened)
    }

    @Test
    @Config(qualifiers = "de")
    fun victoriaHeadingIsTranslatedAndLicenceLineStaysEnglish() {
        show("de")
        composeRule.onNodeWithText("VICTORIA, AUSTRALIEN").assertExists()
        composeRule.onNodeWithText(DataCredits.PTV_LICENCE).assertExists()
    }
}
