package com.evanjt.traintime.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.data.model.Formation
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// The formation on a round watch face at the tracking screen's padding, with one car
// highlighted so the readout and its ring show.
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class FormationSnapshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun capture(name: String, formation: Formation, screen: Dp, cursor: Int) {
        composeRule.setContent {
            Column(
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .size(screen)
                    .clip(CircleShape)
                    .background(Color.Black)
                    .padding(horizontal = 12.dp),
            ) {
                BoxWithConstraints(Modifier.fillMaxWidth()) {
                    val strip = FormationStrip(maxWidth.value, formation.wagons.map { it.noPassageAfter })
                    FormationStripWear(formation, strip, cursor)
                }
                FormationReadoutWear(formation.wagons[cursor], left = 0.6f, modifier = Modifier.padding(top = 4.dp))
            }
        }
        composeRule.onRoot().captureRoboImage("src/test/screenshots/$name.png", roborazziOptions = TOLERANT)
    }

    private companion object {
        // Absorb minor anti-aliasing differences between local and CI rendering.
        val TOLERANT = RoborazziOptions(
            compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0.01f),
        )
    }

    @Test fun longTrainSmallRound() = capture("formation_708_small", FormationFixtures.ic708, 192.dp, cursor = 12)

    @Test fun longTrainLargeRound() = capture("formation_708_large", FormationFixtures.ic708, 227.dp, cursor = 12)

    @Test fun reversedTrainSmallRound() = capture("formation_977_small", FormationFixtures.ic977, 192.dp, cursor = 0)
}
