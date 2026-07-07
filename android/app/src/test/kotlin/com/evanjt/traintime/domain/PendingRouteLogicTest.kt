package com.evanjt.traintime.domain

import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.data.sbb.LegType
import com.evanjt.traintime.data.sbb.RouteLeg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingRouteLogicTest {
    private val now = 1_800_000_000L

    private fun ride(dep: Long, arr: Long = dep + 3600, train: String? = "1820") = RouteLeg(
        type = LegType.RIDE,
        originId = "8501506",
        originName = "Sion",
        originLat = 46.2276,
        originLon = 7.3607,
        destId = "8501120",
        destName = "Lausanne",
        depTs = dep,
        arrTs = arr,
        category = "IR",
        lineNumber = "90",
        trainNumber = train,
    )

    // A ride starting outside Switzerland: no departure board, so untrackable.
    private fun foreignRide(dep: Long, arr: Long = dep + 3600) = RouteLeg(
        type = LegType.RIDE,
        originId = "8300000",
        originName = "Torino",
        originLat = 45.0703,
        originLon = 7.6869,
        destId = "8300001",
        destName = "Milano",
        depTs = dep,
        arrTs = arr,
        category = "EC",
        lineNumber = "40",
        trainNumber = "9",
    )

    private fun walk(dep: Long, arr: Long) = RouteLeg(
        type = LegType.WALK,
        originName = "somewhere",
        destName = "Sion",
        depTs = dep,
        arrTs = arr,
    )

    private fun route(
        vararg legs: RouteLeg,
        cursor: Int = 0,
        status: String = PendingRoute.STATUS_SAVED,
        muted: List<Int> = emptyList(),
    ) = PendingRoute(
        id = "r1",
        legs = legs.toList(),
        finalDestination = "Lausanne",
        cursor = cursor,
        status = status,
        createdTs = now - 3600,
        mutedLegIndices = muted,
    )

    @Test
    fun `normalize keeps a future leg untouched`() {
        val r = route(ride(now + 7200))
        assertEquals(r, PendingRouteLogic.normalize(r, now))
    }

    @Test
    fun `normalize skips walks and missed rides to the next viable leg`() {
        val r = route(
            walk(now - 7200, now - 7000),
            ride(now - 7000, now - 3600, train = "1"),
            ride(now + 3600, train = "2"),
        )
        val normalized = PendingRouteLogic.normalize(r, now)!!
        assertEquals(2, normalized.cursor)
        assertEquals("2", normalized.currentLeg!!.trainNumber)
    }

    @Test
    fun `normalize expires when every ride has left`() {
        assertNull(PendingRouteLogic.normalize(route(ride(now - 7200), ride(now - 3600)), now))
    }

    @Test
    fun `normalize is idempotent`() {
        val r = route(ride(now - 7000, train = "1"), ride(now + 3600, train = "2"))
        val once = PendingRouteLogic.normalize(r, now)!!
        assertEquals(once, PendingRouteLogic.normalize(once, now))
    }

    @Test
    fun `normalize resets tracking status when it advances`() {
        val r = route(
            ride(now - 7000, train = "1"),
            ride(now + 3600, train = "2"),
            cursor = 0,
            status = PendingRoute.STATUS_TRACKING,
        )
        assertEquals(PendingRoute.STATUS_SAVED, PendingRouteLogic.normalize(r, now)!!.status)
    }

    @Test
    fun `notifyTs uses the fifteen minute floor`() {
        val dep = now + 7200
        assertEquals(dep - 15 * 60, PendingRouteLogic.notifyTs(route(ride(dep)))!!)
    }

    @Test
    fun `notifyTs stretches for a long preceding walk`() {
        val dep = now + 7200
        val r = route(walk(dep - 1500, dep - 60), ride(dep), cursor = 1)
        // 24 min walk + 5 min margin beats the 15 min floor.
        assertEquals(dep - (1440 + 300), PendingRouteLogic.notifyTs(r)!!)
    }

    @Test
    fun `connection leg uses the shorter connection lead`() {
        val dep = now + 7200
        // First ride already departed, cursor on the second ride (a connection).
        val r = route(
            ride(now - 3600, train = "1"),
            walk(dep - 120, dep - 30),
            ride(dep, train = "2"),
            cursor = 2,
        )
        assertEquals(dep - 3 * 60, PendingRouteLogic.notifyTs(r)!!)
    }

    @Test
    fun `leads are configurable and independent`() {
        val dep = now + 7200
        val first = route(ride(dep))
        assertEquals(dep - 10 * 60, PendingRouteLogic.notifyTs(first, savedLeadSec = 10 * 60)!!)
        val connection = route(ride(now - 3600, train = "1"), ride(dep, train = "2"), cursor = 1)
        assertEquals(dep - 4 * 60, PendingRouteLogic.notifyTs(connection, connectionLeadSec = 4 * 60)!!)
    }

    @Test
    fun `distance adds walk time to the buffer`() {
        val dep = now + 7200
        // 830 m ≈ 10 min walk at 83 m/min, + 5 min buffer = 15 min lead.
        val r = route(ride(dep))
        assertEquals(dep - (10 + 5) * 60, PendingRouteLogic.notifyTs(r, savedLeadSec = 5 * 60, userDistanceMeters = 830.0)!!)
    }

    @Test
    fun `distance lead is capped`() {
        val dep = now + 100_000
        // 100 km would be ~20 h walk, must clamp to MAX_LEAD_SEC.
        val r = route(ride(dep))
        assertEquals(dep - PendingRouteLogic.MAX_LEAD_SEC, PendingRouteLogic.notifyTs(r, userDistanceMeters = 100_000.0)!!)
    }

    @Test
    fun `nil distance keeps the static lead`() {
        val dep = now + 7200
        val r = route(ride(dep))
        assertEquals(dep - 15 * 60, PendingRouteLogic.notifyTs(r, userDistanceMeters = null)!!)
    }

    @Test
    fun `connection leg ignores distance`() {
        val dep = now + 7200
        val r = route(ride(now - 3600, train = "1"), ride(dep, train = "2"), cursor = 1)
        assertEquals(dep - 3 * 60, PendingRouteLogic.notifyTs(r, userDistanceMeters = 5000.0)!!)
    }

    @Test
    fun `isConnectionLeg true only past the first ride`() {
        assertFalse(PendingRouteLogic.isConnectionLeg(route(ride(now + 3600))))
        val r = route(ride(now - 3600, train = "1"), ride(now + 3600, train = "2"), cursor = 1)
        assertTrue(PendingRouteLogic.isConnectionLeg(r))
    }

    @Test
    fun `isResumable only inside the window`() {
        assertTrue(PendingRouteLogic.isResumable(route(ride(now + 44 * 60)), now))
        assertFalse(PendingRouteLogic.isResumable(route(ride(now + 46 * 60)), now))
        assertFalse(PendingRouteLogic.isResumable(route(ride(now - 200)), now))
    }

    @Test
    fun `muted current leg gets no reminder and no resume offer`() {
        val r = route(ride(now + 30 * 60), muted = listOf(0))
        assertNull(PendingRouteLogic.notifyTs(r))
        assertFalse(PendingRouteLogic.isResumable(r, now))
    }

    @Test
    fun `untrackable current leg gets no reminder and no resume offer`() {
        val r = route(foreignRide(now + 30 * 60))
        assertNull(PendingRouteLogic.notifyTs(r))
        assertFalse(PendingRouteLogic.isResumable(r, now))
    }

    @Test
    fun `unmuting a leg restores the reminder`() {
        val r = route(ride(now + 30 * 60))
        assertEquals(now + 30 * 60 - 15 * 60, PendingRouteLogic.notifyTs(r)!!)
    }

    @Test
    fun `fingerprint stable for the same first ride`() {
        val a = route(walk(now, now + 100), ride(now + 3600))
        val b = route(ride(now + 3600))
        assertEquals(PendingRouteLogic.fingerprint(a), PendingRouteLogic.fingerprint(b))
    }

    @Test
    fun `advance moves to the next leg when the tracked leg departed`() {
        val dep = now - 120
        val r = route(
            ride(dep, train = "1"),
            walk(now - 60, now + 300),
            ride(now + 3600, train = "2"),
            status = PendingRoute.STATUS_TRACKING,
        )
        val advanced = PendingRouteLogic.advancedAfterTracking(r, endedDepTs = dep, now = now)!!
        assertEquals(2, advanced.cursor)
        assertEquals(PendingRoute.STATUS_SAVED, advanced.status)
    }

    @Test
    fun `advance expires a single-leg route after departure`() {
        val dep = now - 120
        val r = route(ride(dep), status = PendingRoute.STATUS_TRACKING)
        assertNull(PendingRouteLogic.advancedAfterTracking(r, endedDepTs = dep, now = now))
    }

    @Test
    fun `early manual exit reverts to saved on the same leg`() {
        val dep = now + 3600
        val r = route(ride(dep), status = PendingRoute.STATUS_TRACKING)
        val reverted = PendingRouteLogic.advancedAfterTracking(r, endedDepTs = dep, now = now)!!
        assertEquals(0, reverted.cursor)
        assertEquals(PendingRoute.STATUS_SAVED, reverted.status)
    }

    @Test
    fun `unrelated tracking end leaves pending untouched`() {
        val r = route(ride(now + 3600), status = PendingRoute.STATUS_TRACKING)
        assertEquals(r, PendingRouteLogic.advancedAfterTracking(r, endedDepTs = now + 999, now = now))
        val saved = route(ride(now + 3600))
        assertEquals(saved, PendingRouteLogic.advancedAfterTracking(saved, endedDepTs = now + 3600, now = now))
    }
}
