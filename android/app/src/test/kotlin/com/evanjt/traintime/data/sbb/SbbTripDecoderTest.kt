package com.evanjt.traintime.data.sbb

import com.evanjt.traintime.data.model.Departure
import java.util.Base64
import java.util.zip.Deflater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

// Fixture captured live from https://a.sbbmobile.ch/s/SA5YK2Z1 on 2026-07-05:
// walk (GPS point → Sion) → IR 90 1820 (Sion 13:02 → Lausanne 14:12) →
// walk (→ Lausanne, gare). Frozen so tests never touch the network.
class SbbTripDecoderTest {
    private val fixtureBlob: String =
        javaClass.classLoader!!.getResource("sbb_trip_fixture.txt")!!.readText().trim()

    private val rideDep = 1783249320L // 2026-07-05 13:02 Europe/Zurich (CEST)
    private val rideArr = 1783253520L

    private fun departure(
        trainNumber: String? = "1820",
        timestamp: Long = rideDep,
        lineNumber: String = "IR90",
        destination: String = "Genève-Aéroport",
    ) = Departure(
        destination = destination,
        minutesUntil = 10,
        departureTimestamp = timestamp,
        delay = 0,
        platform = "3",
        platformChanged = false,
        lineNumber = lineNumber,
        category = "IR",
        trainNumber = trainNumber,
        operatorRef = "11",
    )

    // Builds a decodable blob from a raw recon string, for cases the frozen
    // fixture can't cover (DST, walk-only, malformed sections).
    private fun syntheticBlob(recon: String, version: String = "3HA"): String {
        val deflater = Deflater()
        deflater.setInput(recon.toByteArray(Charsets.UTF_8))
        deflater.finish()
        val buffer = ByteArray(recon.length * 2 + 64)
        val n = deflater.deflate(buffer)
        deflater.end()
        val b64 = Base64.getUrlEncoder().withoutPadding().encodeToString(buffer.copyOf(n))
        return "$version.$b64"
    }

    private fun rideRecon(vararg legs: String) =
        "¶HKI¶" + legs.joinToString("§") + "¶GP¶x"

    private fun rideLeg(dep: String, arr: String, line: String = "IC 8 824") =
        "T\$A=1@O=Visp@X=7881465@Y=46294029@L=8501609@a=128@\$" +
            "A=1@O=Brig@X=7988095@Y=46319423@L=8501605@a=128@\$$dep\$$arr\$$line\$\$1\$\$\$\$\$"

    @Test
    fun `findIn recognises short link amid share text`() {
        val link = SbbShareLink.findIn(
            "Check out my trip! https://a.sbbmobile.ch/s/SA5YK2Z1 sent from SBB Mobile",
        )
        assertEquals(SbbShareLink.Short("https://a.sbbmobile.ch/s/SA5YK2Z1"), link)
    }

    @Test
    fun `findIn recognises recon and tripId links`() {
        assertEquals(
            SbbShareLink.Blob(fixtureBlob),
            SbbShareLink.findIn("sbbmobile://trip?recon=$fixtureBlob"),
        )
        assertEquals(
            SbbShareLink.Blob(fixtureBlob),
            SbbShareLink.findIn("see https://www.sbb.ch/en/trip?tripId=$fixtureBlob ok"),
        )
    }

    @Test
    fun `findIn returns null on unrelated text`() {
        assertNull(SbbShareLink.findIn("meet me at the station at 13:02, https://example.com/x"))
    }

    @Test
    fun `decodes the frozen fixture into three legs`() {
        val route = SbbTripDecoder.decode(fixtureBlob)
        assertEquals(3, route.legs.size)

        val walkIn = route.legs[0]
        assertEquals(LegType.WALK, walkIn.type)
        assertNull(walkIn.originId)
        assertEquals("Sion", walkIn.destName)
        assertEquals("8501506", walkIn.destId)
        assertEquals(1783248600L, walkIn.depTs)

        val ride = route.legs[1]
        assertEquals(LegType.RIDE, ride.type)
        assertEquals("8501506", ride.originId)
        assertEquals("Sion", ride.originName)
        assertEquals("8501120", ride.destId)
        assertEquals("Lausanne", ride.destName)
        assertEquals(rideDep, ride.depTs)
        assertEquals(rideArr, ride.arrTs)
        assertEquals("IR", ride.category)
        assertEquals("90", ride.lineNumber)
        assertEquals("1820", ride.trainNumber)
        assertEquals(46.227549, ride.originLat!!, 1e-9)
        assertEquals(7.359199, ride.originLon!!, 1e-9)

        val walkOut = route.legs[2]
        assertEquals(LegType.WALK, walkOut.type)
        assertEquals("Lausanne, gare", walkOut.destName)
        assertEquals("8592050", walkOut.destId)
        assertEquals(1783253820L, walkOut.arrTs)

        assertEquals("Lausanne, gare", route.finalDestinationName)
    }

    @Test
    fun `winter times convert with CET offset`() {
        val blob = syntheticBlob(rideRecon(rideLeg("202612051302", "202612051412")))
        val route = SbbTripDecoder.decode(blob)
        assertEquals(1796472120L, route.legs[0].depTs) // 2026-12-05 13:02 +01:00
    }

    @Test
    fun `targetRideLegIndex picks the catchable ride`() {
        val route = SbbTripDecoder.decode(fixtureBlob)
        assertEquals(1, route.targetRideLegIndex(rideDep - 3600))
        assertEquals(1, route.targetRideLegIndex(rideDep + 60)) // grace window
        assertNull(route.targetRideLegIndex(rideDep + 61))
    }

    @Test
    fun `mid-route share targets the next connection`() {
        val blob = syntheticBlob(
            rideRecon(
                rideLeg("202607051302", "202607051340", "IC 8 824"),
                rideLeg("202607051350", "202607051500", "IC 1 717"),
            ),
        )
        val route = SbbTripDecoder.decode(blob)
        val onFirstTrain = 1783249320L + 600 // ten minutes after leg 1 departed
        assertEquals(1, route.targetRideLegIndex(onFirstTrain))
    }

    @Test
    fun `matchDeparture prefers exact train number and timestamp`() {
        val route = SbbTripDecoder.decode(fixtureBlob)
        val leg = route.legs[1]
        val exact = departure()
        val decoy = departure(trainNumber = "1822", timestamp = rideDep + 1800)
        assertEquals(exact, matchDeparture(listOf(decoy, exact), leg))
    }

    @Test
    fun `matchDeparture falls back to normalised line within a minute`() {
        val leg = SbbTripDecoder.decode(fixtureBlob).legs[1]
        val board = listOf(departure(trainNumber = null, timestamp = rideDep + 30))
        assertEquals(board[0], matchDeparture(board, leg))
    }

    @Test
    fun `matchDeparture never matches on destination alone`() {
        val leg = SbbTripDecoder.decode(fixtureBlob).legs[1]
        val wrongTrain = departure(
            trainNumber = "9999",
            timestamp = rideDep + 3600,
            lineNumber = "IC5",
            destination = "Lausanne",
        )
        assertNull(matchDeparture(listOf(wrongTrain), leg))
    }

    @Test
    fun `unsupported version is rejected`() {
        val blob = syntheticBlob(rideRecon(rideLeg("202607051302", "202607051412")), version = "4XA")
        val e = assertThrows(SbbDecodeException::class.java) { SbbTripDecoder.decode(blob) }
        assertEquals(SbbDecodeException.Reason.UNSUPPORTED_VERSION, e.reason)
    }

    @Test
    fun `truncated blob is malformed`() {
        val e = assertThrows(SbbDecodeException::class.java) {
            SbbTripDecoder.decode(fixtureBlob.substring(0, 40))
        }
        assertEquals(SbbDecodeException.Reason.MALFORMED, e.reason)
    }

    @Test
    fun `walk-only trip has nothing to track`() {
        val walk = "W\$A=1@O=Sion@L=8501506@a=128@\$A=1@O=Sion, gare@L=8588983@a=128@\$" +
            "202607051250\$202607051255\$\$\$1\$\$\$\$\$"
        val e = assertThrows(SbbDecodeException::class.java) {
            SbbTripDecoder.decode(syntheticBlob(rideRecon(walk)))
        }
        assertEquals(SbbDecodeException.Reason.NO_RIDE_LEGS, e.reason)
    }

    @Test
    fun `extractBlobFromHtml finds the splash anchor`() {
        val html = """<a id="appLink" href="sbbmobile://trip?recon=$fixtureBlob">Open</a>"""
        assertEquals(fixtureBlob, SbbTripDecoder.extractBlobFromHtml(html))
    }
}
