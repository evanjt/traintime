package com.evanjt.traintime.wear

import com.evanjt.traintime.core.sync.TrackCommand
import com.evanjt.traintime.core.sync.WearCommand
import com.evanjt.traintime.core.sync.WearCommandBus
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.core.sync.WearSyncPort
import com.evanjt.traintime.data.model.TransportMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

// Liveness announcements and the phone-mirror command contract, driven through
// a recording fake of the Data Layer port. runCurrent (never advanceUntilIdle):
// the refresh timer is an endless delay loop.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WearViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setMainDispatcher() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun resetMainDispatcher() {
        Dispatchers.resetMain()
    }

    private class RecordingSync : WearSyncPort {
        override var isWatch = false
        val liveness = mutableListOf<String>()

        override suspend fun pushState() {}

        override suspend fun sendLiveness(kind: String, tracking: com.evanjt.traintime.core.sync.TrackCommand?) {
            liveness += kind
        }

        override suspend fun sendReminder(cmd: com.evanjt.traintime.core.sync.ReminderCommand): Boolean = false

        override suspend fun connectedWatchNames(): List<String> = emptyList()

        override suspend fun appInstalledWatchNames(): List<String> = emptyList()
    }

    private fun viewModel(sync: RecordingSync) =
        WearViewModel(RuntimeEnvironment.getApplication(), sync)

    // Bus category so beginTracking never fetches a formation (no network in tests).
    private fun busTrack() = TrackCommand(
        destination = "Bern",
        departureTimestamp = System.currentTimeMillis() / 1000 + 540,
        lineNumber = "7",
        category = "B",
        stationId = "8507000",
    )

    @Test
    fun marksItselfAsWatchAndAnnouncesLifecycle() {
        val sync = RecordingSync()
        val vm = viewModel(sync)
        dispatcher.scheduler.runCurrent()
        assertTrue(sync.isWatch)

        vm.onAppear()
        dispatcher.scheduler.runCurrent()
        assertTrue(WearSync.KIND_HELLO in sync.liveness)

        vm.onDisappear()
        dispatcher.scheduler.runCurrent()
        assertEquals(WearSync.KIND_BYE, sync.liveness.last())
    }

    @Test
    fun phoneModeCommandSwitchesTheBoard() {
        val sync = RecordingSync()
        val vm = viewModel(sync)
        dispatcher.scheduler.runCurrent()
        assertEquals(TransportMode.TRAIN, vm.currentMode)

        WearCommandBus.events.tryEmit(WearCommand(action = "mode", mode = TransportMode.TRAM.raw))
        dispatcher.scheduler.runCurrent()
        assertEquals(TransportMode.TRAM, vm.currentMode)
    }

    @Test
    fun trackCommandEntersTrackingAndMirrorCommandsAreThenIgnored() {
        val sync = RecordingSync()
        val vm = viewModel(sync)
        dispatcher.scheduler.runCurrent()

        vm.handleTrackCommand(busTrack())
        assertEquals(2, vm.appState)
        assertEquals("Bern", vm.focusedTrain?.destination)

        WearCommandBus.events.tryEmit(WearCommand(action = "mode", mode = TransportMode.TRAM.raw))
        dispatcher.scheduler.runCurrent()
        assertEquals(TransportMode.TRAIN, vm.currentMode)

        vm.exitToStationView()
        assertEquals(0, vm.appState)
    }
}
