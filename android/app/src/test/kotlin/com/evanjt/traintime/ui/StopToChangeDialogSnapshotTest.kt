package com.evanjt.traintime.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.test.junit4.createComposeRule
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.ui.adaptive.BoardPicker
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureScreenRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class StopToChangeDialogSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @OptIn(ExperimentalRoborazziApi::class)
    private fun capture(name: String, picker: BoardPicker) {
        composeRule.setContent {
            MaterialTheme(colorScheme = lightColorScheme()) {
                StopToChangeDialog(picker = picker, onConfirm = {}, onDismiss = {})
            }
        }
        captureScreenRoboImage("src/test/screenshots/$name.png", roborazziOptions = TOLERANT)
    }

    private companion object {
        val TOLERANT = RoborazziOptions(
            compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0.01f),
        )
    }

    @Test
    fun stopToChangeStation() = capture("stop_to_change_station", BoardPicker.Station)

    @Test
    fun stopToChangeMode() = capture("stop_to_change_mode", BoardPicker.Mode(TransportMode.BUS))
}
