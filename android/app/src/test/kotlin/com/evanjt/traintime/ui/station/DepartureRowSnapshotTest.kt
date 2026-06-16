package com.evanjt.traintime.ui.station

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.LightPalette
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.TransportMode
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// Screenshot regression for the departure row: line pills (long-distance red,
// regional blue, bus grey-blue), delay capsule, and the favourite gold row.
// Renders on the JVM via Robolectric — no emulator. Golden lives under
// src/test/screenshots; CI runs verifyRoborazziDebug.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class DepartureRowSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun dep(line: String, dest: String, min: Int, delay: Int = 0) = Departure(
        destination = dest,
        minutesUntil = min,
        departureTimestamp = 1000L,
        delay = delay,
        platform = "3",
        platformChanged = false,
        lineNumber = line,
        category = "IC",
        trainNumber = null,
        operatorRef = null,
    )

    @Test
    fun departureRows() {
        composeRule.setContent {
            CompositionLocalProvider(LocalAppPalette provides LightPalette) {
                MaterialTheme {
                    Surface {
                        Column(Modifier.width(360.dp)) {
                            DepartureRow(dep("IR15", "Luzern", 6), isFavourite = false, mode = TransportMode.TRAIN)
                            DepartureRow(dep("IC8", "Romanshorn", 8, delay = 1), isFavourite = false, mode = TransportMode.TRAIN)
                            DepartureRow(dep("S7", "Worb Dorf", 6), isFavourite = true, mode = TransportMode.TRAIN)
                            DepartureRow(dep("12", "Sion", 4), isFavourite = false, mode = TransportMode.BUS)
                        }
                    }
                }
            }
        }
        composeRule.onRoot().captureRoboImage("src/test/screenshots/departure_rows.png")
    }
}
