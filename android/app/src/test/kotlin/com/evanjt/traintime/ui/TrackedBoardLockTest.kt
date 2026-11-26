package com.evanjt.traintime.ui

import androidx.test.core.app.ApplicationProvider
import com.evanjt.traintime.data.api.NearbyStations
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.ui.adaptive.BoardPicker
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Scenario: a departure is tracked and a mode or station change reaches the
// view model without passing the locked pickers.
// Expected behaviour: the board keeps its mode and station and the session its
// departure. The same calls move the board once nothing is tracked.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TrackedBoardLockTest {
    private val viewModel = MainViewModel(ApplicationProvider.getApplicationContext())

    private fun departure(destination: String, line: String) = Departure(
        destination = destination,
        minutesUntil = 10,
        departureTimestamp = System.currentTimeMillis() / 1000 + 600,
        delay = 0,
        platform = "",
        platformChanged = false,
        lineNumber = line,
        category = "B",
        trainNumber = null,
        operatorRef = null,
    )

    // Every station carries its own board, so a change of station never fetches.
    private fun station(id: String, name: String, mode: TransportMode, destination: String) = Station(
        id = id,
        name = name,
        lat = null,
        lon = null,
        mode = mode,
        embeddedDepartures = listOf(departure(destination, "7")),
    )

    @Before
    fun showTwoModes() {
        viewModel.showNearby(
            NearbyStations(
                train = listOf(
                    station("alder", "Alder Row", TransportMode.TRAIN, "Fenwick"),
                    station("birch", "Birch Quay", TransportMode.TRAIN, "Garsdale"),
                ),
                bus = listOf(station("cedar", "Cedar Halt", TransportMode.BUS, "Holme")),
                tram = emptyList(),
                special = emptyList(),
            ),
        )
        assertEquals(TransportMode.TRAIN, viewModel.currentMode)
        assertEquals("alder", viewModel.currentStation?.id)
    }

    @After
    fun endSession() {
        viewModel.stopSession(discardRoute = false)
    }

    private fun track() {
        viewModel.selectDeparture(0)
        assertEquals(2, viewModel.appState)
        assertEquals("Fenwick", viewModel.focusedTrain?.destination)
    }

    @Test fun aModeChangeWhileTrackingIsRefused() {
        track()
        val tracked = viewModel.focusedTrain

        viewModel.selectMode(TransportMode.BUS)

        assertEquals(TransportMode.TRAIN, viewModel.currentMode)
        assertEquals("alder", viewModel.currentStation?.id)
        assertEquals("Fenwick", viewModel.departures.single().destination)
        assertEquals(2, viewModel.appState)
        assertEquals(tracked, viewModel.focusedTrain)
    }

    @Test fun aStationChangeWhileTrackingIsRefused() {
        track()
        val tracked = viewModel.focusedTrain

        viewModel.selectStation(1)

        assertEquals(TransportMode.TRAIN, viewModel.currentMode)
        assertEquals("alder", viewModel.currentStation?.id)
        assertEquals("Fenwick", viewModel.departures.single().destination)
        assertEquals(2, viewModel.appState)
        assertEquals(tracked, viewModel.focusedTrain)
    }

    @Test fun aRefusedStationChangeClosesTheSheetItCameFrom() {
        track()
        viewModel.showStationPicker = true

        viewModel.selectStation(1)

        assertEquals(false, viewModel.showStationPicker)
    }

    @Test fun modeAndStationChangeWhenNothingIsTracked() {
        viewModel.selectStation(1)
        assertEquals("birch", viewModel.currentStation?.id)

        viewModel.selectMode(TransportMode.BUS)
        assertEquals(TransportMode.BUS, viewModel.currentMode)
        assertEquals("cedar", viewModel.currentStation?.id)
    }

    @Test fun aConfirmedPickerTapStopsTrackingThenChangesMode() {
        track()

        viewModel.tapPicker(BoardPicker.Mode(TransportMode.BUS))
        assertNotNull(viewModel.pendingPicker)
        assertEquals(TransportMode.TRAIN, viewModel.currentMode)

        viewModel.confirmPicker()

        assertEquals(0, viewModel.appState)
        assertNull(viewModel.focusedTrain)
        assertEquals(TransportMode.BUS, viewModel.currentMode)
        assertEquals("cedar", viewModel.currentStation?.id)
    }
}
