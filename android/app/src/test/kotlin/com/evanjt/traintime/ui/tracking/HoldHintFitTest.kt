package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LightPalette
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.session.MuteLook
import com.evanjt.traintime.session.MuteState
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// Scenario: all four actions on a 360dp phone, the narrowest the row is laid out for.
// Expected behaviour: the hold hint under Sound and Buzz sits on one line in every
// language, never clipped.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class HoldHintFitTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun assertHintFits() {
        var needed = 0
        composeRule.setContent {
            CompositionLocalProvider(LocalAppPalette provides LightPalette) {
                MaterialTheme(colorScheme = lightColorScheme()) {
                    Surface {
                        val text = stringResource(R.string.trip_hold_hint)
                        needed = rememberTextMeasurer()
                            .measure(text, LocalTextStyle.current.copy(fontSize = 11.sp), softWrap = false)
                            .size.width
                        TrackingActionRow(
                            showMap = true,
                            watch = WatchAction(trackingHere = false, checking = false, liveness = WatchLiveness.OPEN),
                            sound = MuteState(MuteLook.ON, usuallyOn = true),
                            buzz = MuteState(MuteLook.ON, usuallyOn = true),
                            onMap = {}, onWatch = {}, onWatchHold = {}, onSound = {}, onSoundHold = {}, onBuzz = {}, onBuzzHold = {},
                            modifier = Modifier.width(360.dp).padding(horizontal = 16.dp),
                        )
                    }
                }
            }
        }
        val room = composeRule.onNodeWithTag(HOLD_HINT_TAG, useUnmergedTree = true).fetchSemanticsNode().size.width
        assertTrue("hint needs $needed px, has $room", needed in 1..room)
    }

    @Test fun english() = assertHintFits()

    @Test @Config(qualifiers = "de-w360dp-h800dp") fun german() = assertHintFits()

    @Test @Config(qualifiers = "fr-w360dp-h800dp") fun french() = assertHintFits()

    @Test @Config(qualifiers = "it-w360dp-h800dp") fun italian() = assertHintFits()
}
