package com.evanjt.traintime.data.api

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

// Scenario: two hosts, the primary misbehaves in the ways a dead home link
// or an overloaded server shows. Expected behaviour: transport errors,
// timeouts, 5xx and 429 on the primary fall through to the fallback once,
// client errors do not, and the fallback stays preferred for five minutes.
class TrainApiFailoverTest {
    private lateinit var primary: MockWebServer
    private lateinit var fallback: MockWebServer
    private lateinit var api: TrainApi

    private var now = 1718000000L
    private val empty = """{"departures": []}"""

    @Before
    fun setUp() {
        primary = MockWebServer()
        fallback = MockWebServer()
        primary.start()
        fallback.start()
        api = TrainApi(
            baseUrls = listOf(primary.url("/").toString(), fallback.url("/").toString()),
            apiKey = "test-key",
            clock = { now },
        )
    }

    @After
    fun tearDown() {
        primary.shutdown()
        fallback.shutdown()
    }

    private suspend fun fetch() = api.fetchDepartures("8501120")

    private suspend fun httpError(): Int {
        try {
            fetch()
        } catch (e: TrainApiException.Http) {
            return e.code
        }
        throw AssertionError("expected TrainApiException.Http")
    }

    @Test
    fun `503 on the primary uses the fallback once`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(503))
        fallback.enqueue(MockResponse().setBody(empty))

        fetch()

        assertEquals(1, primary.requestCount)
        assertEquals(1, fallback.requestCount)
    }

    @Test
    fun `429 on the primary uses the fallback once`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(429))
        fallback.enqueue(MockResponse().setBody(empty))

        fetch()

        assertEquals(1, primary.requestCount)
        assertEquals(1, fallback.requestCount)
    }

    @Test
    fun `disconnect on the primary uses the fallback once`() = runTest {
        primary.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
        fallback.enqueue(MockResponse().setBody(empty))

        fetch()

        assertEquals(1, primary.requestCount)
        assertEquals(1, fallback.requestCount)
    }

    @Test
    fun `body delay past the first attempt timeout uses the fallback`() = runTest {
        primary.enqueue(MockResponse().setBody(empty).setBodyDelay(6, TimeUnit.SECONDS))
        fallback.enqueue(MockResponse().setBody(empty))

        val started = System.nanoTime()
        fetch()
        val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)

        assertEquals(1, fallback.requestCount)
        assertTrue("took $elapsedMs ms", elapsedMs in 2500..5000)
    }

    @Test
    fun `400 401 and 404 on the primary never reach the fallback`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(400))
        primary.enqueue(MockResponse().setResponseCode(401))
        primary.enqueue(MockResponse().setResponseCode(404))

        assertEquals(400, httpError())
        try {
            fetch()
            throw AssertionError("expected UpdateRequired")
        } catch (e: TrainApiException.UpdateRequired) {
            // expected
        }
        assertEquals(404, httpError())

        assertEquals(3, primary.requestCount)
        assertEquals(0, fallback.requestCount)
    }

    @Test
    fun `the call after a failure goes to the fallback only`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(503))
        fallback.enqueue(MockResponse().setBody(empty))
        fallback.enqueue(MockResponse().setBody(empty))

        fetch()
        fetch()

        assertEquals(1, primary.requestCount)
        assertEquals(2, fallback.requestCount)
    }

    @Test
    fun `the primary is retried after the reprobe window`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(503))
        primary.enqueue(MockResponse().setBody(empty))
        fallback.enqueue(MockResponse().setBody(empty))

        fetch()
        now += 301
        fetch()

        assertEquals(2, primary.requestCount)
        assertEquals(1, fallback.requestCount)
    }

    @Test
    fun `both hosts failing raises the last attempt's error`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(503))
        fallback.enqueue(MockResponse().setResponseCode(503))

        assertEquals(503, httpError())
        assertEquals(1, primary.requestCount)
        assertEquals(1, fallback.requestCount)
    }

    @Test
    fun `fallback 429 after primary 503 raises RateLimited`() = runTest {
        primary.enqueue(MockResponse().setResponseCode(503))
        fallback.enqueue(MockResponse().setResponseCode(429))

        try {
            fetch()
            throw AssertionError("expected RateLimited")
        } catch (e: TrainApiException.RateLimited) {
            // expected
        }
    }

    @Test
    fun `a single host list has no fallback`() = runTest {
        val single = TrainApi(baseUrls = listOf(primary.url("/").toString()), apiKey = "k", clock = { now })
        primary.enqueue(MockResponse().setResponseCode(503))

        try {
            single.fetchDepartures("8501120")
            throw AssertionError("expected Http")
        } catch (e: TrainApiException.Http) {
            assertEquals(503, e.code)
        }
        assertEquals(1, primary.requestCount)
    }
}
