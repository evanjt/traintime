package com.evanjt.traintime.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.data.model.TransportMode
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// Watch line pills down a leg list: one width whatever the label, the label centred.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class WearLinePillTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val labels = listOf("S3", "IR95", "BEG", "16", "V41", "RE33X", "ICE1234")

    private fun pills() {
        composeRule.setContent {
            Column(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.background(Color.Black).padding(8.dp),
            ) {
                labels.forEach { line ->
                    WearLinePill(line, WearDarkPalette.linePill(line, TransportMode.TRAIN), fontSize = 11.sp)
                }
            }
        }
    }

    @Test
    fun linePillsShareOneWidthWhateverTheLabel() {
        pills()
        val widths = labels.map { label ->
            val bounds = composeRule.onNodeWithText(label).getBoundsInRoot()
            bounds.right - bounds.left
        }
        assertEquals(labels.map { widths.first() }, widths)
    }

    @Test
    fun linePillsSnapshot() {
        pills()
        composeRule.onRoot().captureRoboImage(
            "src/test/screenshots/wear_line_pills.png",
            roborazziOptions = RoborazziOptions(
                compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0.01f),
            ),
        )
    }
}
