package com.evanjt.traintime.wear

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.evanjt.traintime.DataCredits
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DataAttributionFooterTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun footerCreditsBothDataSources() {
        composeRule.setContent { Column { DataAttributionFooter() } }
        composeRule.onNodeWithText("Data: opentransportdata.swiss").assertExists()
        composeRule.onNodeWithText("Victoria, Australia", substring = true).assertExists()
        composeRule.onNodeWithText(
            "Source: Licensed from Public Transport Victoria under a Creative Commons Attribution 4.0 International Licence.",
            substring = true,
        ).assertExists()
    }

    @Test
    @Config(qualifiers = "fr")
    fun footerHeadingIsTranslatedAndLicenceLineStaysEnglish() {
        composeRule.setContent { Column { DataAttributionFooter() } }
        composeRule.onNodeWithText("Victoria, Australie", substring = true).assertExists()
        composeRule.onNodeWithText(DataCredits.PTV_LICENCE, substring = true).assertExists()
    }
}
