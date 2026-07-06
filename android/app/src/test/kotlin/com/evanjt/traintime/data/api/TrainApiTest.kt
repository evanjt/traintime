package com.evanjt.traintime.data.api

import com.evanjt.traintime.data.model.TransportMode
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class TrainApiTest {
    private lateinit var server: MockWebServer
    private lateinit var api: TrainApi

    private val now = 1718000000L

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        api = TrainApi(
            baseUrl = server.url("/").toString(),
            apiKey = "test-key",
            clock = { now },
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `nearby parses grouped stations and embedded departures with epoch second timestamps`() = runTest {
        // departure is 600 s after `now`, so minutesUntil must be 10,
        // pins the epoch-seconds unit of the `departure` field.
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "train": [
                    {
                      "id": "8501120",
                      "name": "Lausanne",
                      "lat": 46.516,
                      "lon": 6.629,
                      "dist": 250.0,
                      "departures": [
                        {
                          "to": "Brig",
                          "category": "IC",
                          "number": "IC8",
                          "departure": ${now + 600},
                          "delay": 2,
                          "platform": "3",
                          "platformChanged": false,
                          "trainNumber": "823",
                          "operatorRef": "SBB"
                        }
                      ]
                    }
                  ],
                  "bus": [{"id": "8579204", "name": "Lausanne, Tunnel", "lat": 46.52, "lon": 6.63, "dist": 400.0}],
                  "tram": [],
                  "special": []
                }
                """.trimIndent(),
            ),
        )

        val result = api.fetchStations(46.516, 6.629)

        assertEquals(1, result.train.size)
        val station = result.train.first()
        assertEquals("8501120", station.id)
        assertEquals("Lausanne", station.name)
        assertEquals(250.0, station.dist!!, 0.001)
        assertEquals(TransportMode.TRAIN, station.mode)

        val dep = station.embeddedDepartures!!.first()
        assertEquals("Brig", dep.destination)
        assertEquals("IC8", dep.lineNumber)
        assertEquals("IC", dep.category)
        assertEquals(10, dep.minutesUntil)
        assertEquals(now + 600, dep.departureTimestamp)
        assertEquals(2, dep.delay)
        assertEquals("3", dep.platform)

        assertEquals(1, result.bus.size)
        assertNull(result.bus.first().embeddedDepartures)
        assertTrue(result.tram.isEmpty())

        val request = server.takeRequest()
        assertEquals("test-key", request.headers["X-API-Key"])
        assertEquals("/v1/nearby?lat=46.516&lon=6.629", request.requestUrl!!.encodedPath + "?" + request.requestUrl!!.encodedQuery)
    }

    @Test
    fun `nearby sends mode param for non-train modes`() = runTest {
        server.enqueue(MockResponse().setBody("""{"train":[],"bus":[],"tram":[],"special":[]}"""))
        api.fetchStations(46.5, 6.6, TransportMode.BUS)
        assertEquals("bus", server.takeRequest().requestUrl!!.queryParameter("mode"))
    }

    @Test
    fun `departures parses regular and favourites arrays`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "departures": [
                    {"to": "Genève", "number": "IR90", "departure": ${now + 120}, "delay": null, "platform": "1"},
                    {"to": "Brig", "number": "IC8", "departure": ${now - 90}, "platform": "3"}
                  ],
                  "favourites": [
                    {"to": "Genève", "number": "IR90", "departure": ${now + 120}, "platform": "1"}
                  ]
                }
                """.trimIndent(),
            ),
        )

        val result = api.fetchDepartures("8501120", favourites = "IR90:Genève")

        assertEquals(2, result.departures.size)
        val first = result.departures[0]
        assertEquals(0, first.delay)
        assertEquals(2, first.minutesUntil)
        assertEquals("2'", first.minutesText)
        val gone = result.departures[1]
        assertTrue(gone.isGone)
        assertEquals("gone", gone.minutesText)

        assertEquals(1, result.favourites.size)

        val request = server.takeRequest()
        assertEquals("8501120", request.requestUrl!!.queryParameter("id"))
        assertEquals("20", request.requestUrl!!.queryParameter("limit"))
        assertEquals("IR90:Genève", request.requestUrl!!.queryParameter("favourites"))
    }

    @Test
    fun `departures collapses twin publications of the same train`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "departures": [
                    {"to": "Coppet", "category": "R", "number": "RL4", "departure": ${now + 300}, "platform": "2", "trainNumber": "23153"},
                    {"to": "Coppet", "category": "R", "number": "RL4", "departure": ${now + 300}, "delay": 1, "platform": "2", "trainNumber": "93153"}
                  ]
                }
                """.trimIndent(),
            ),
        )

        val result = api.fetchDepartures("8501014")

        assertEquals(1, result.departures.size)
        assertEquals("93153", result.departures.first().trainNumber)
        assertEquals(1, result.departures.first().delay)
    }

    @Test
    fun `nearby collapses twin publications in embedded departures`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "train": [
                    {"id": "8501014", "name": "Mies", "lat": 46.3, "lon": 6.17, "dist": 100.0, "departures": [
                      {"to": "Coppet", "number": "RL4", "departure": ${now + 300}, "platform": "2", "trainNumber": "23153"},
                      {"to": "Coppet", "number": "RL4", "departure": ${now + 300}, "delay": 1, "platform": "2", "trainNumber": "93153"}
                    ]}
                  ],
                  "bus": [], "tram": [], "special": []
                }
                """.trimIndent(),
            ),
        )

        val embedded = api.fetchStations(46.3, 6.17).train.first().embeddedDepartures!!

        assertEquals(1, embedded.size)
        assertEquals("93153", embedded.first().trainNumber)
    }

    @Test
    fun `departures without favourites field returns empty favourites`() = runTest {
        server.enqueue(MockResponse().setBody("""{"departures": []}"""))
        val result = api.fetchDepartures("8501120")
        assertTrue(result.favourites.isEmpty())
        assertNull(server.takeRequest().requestUrl!!.queryParameter("favourites"))
    }

    @Test
    fun `rate limit raises RateLimited`() = runTest {
        server.enqueue(MockResponse().setResponseCode(429))
        try {
            api.fetchDepartures("8501120")
            throw AssertionError("expected RateLimited")
        } catch (e: TrainApiException.RateLimited) {
            // expected
        }
    }

    @Test
    fun `formation parses wagons with class field`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "track": "3",
                  "sectors": ["A", "B"],
                  "wagons": [
                    {"position": 1, "number": 101, "class": 2, "sector": "A", "features": ["wheelchair"], "closed": false},
                    {"position": 2, "number": 102, "class": 1, "sector": "B"}
                  ]
                }
                """.trimIndent(),
            ),
        )

        val formation = api.fetchFormation("823", "2026-06-12", "8501120", "SBB")!!

        assertEquals("3", formation.track)
        assertEquals(listOf("A", "B"), formation.sectors)
        assertEquals(2, formation.wagons.size)
        assertEquals(2, formation.wagons[0].wagonClass)
        assertEquals(listOf("wheelchair"), formation.wagons[0].features)
        assertEquals(1, formation.wagons[1].wagonClass)

        val request = server.takeRequest()
        assertEquals("823", request.requestUrl!!.queryParameter("train"))
        assertEquals("SBB", request.requestUrl!!.queryParameter("operatorRef"))
    }

    @Test
    fun `formation returns null on http error`() = runTest {
        server.enqueue(MockResponse().setResponseCode(404))
        assertNull(api.fetchFormation("823", "2026-06-12", "8501120"))
    }
}
