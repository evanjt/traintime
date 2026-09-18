package com.evanjt.traintime.data.api

import com.evanjt.traintime.core.BuildConfig
import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.Timing
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.dedupedForDisplay
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

sealed class TrainApiException(message: String) : Exception(message) {
    class RateLimited : TrainApiException("Rate limited")
    class UpdateRequired : TrainApiException("Update required")
    class Http(val code: Int) : TrainApiException("HTTP $code")
    class NoData : TrainApiException("No data")
    class Network : TrainApiException("Network error")

    // Worth another host: the host is down, slow or overloaded rather than
    // rejecting the request itself.
    val retriable: Boolean
        get() = when (this) {
            is Network, is RateLimited -> true
            is Http -> HostFailover.shouldFailover(code)
            else -> false
        }
}

data class NearbyStations(
    val train: List<Station>,
    val bus: List<Station>,
    val tram: List<Station>,
    val special: List<Station>,
)

data class DeparturesResult(
    val departures: List<Departure>,
    val favourites: List<Departure>,
)

// Port of apple/TrainTimeWatch/Services/TrainAPIService.swift.
class TrainApi(
    baseUrls: List<String>? = null,
    private val apiKey: String = BuildConfig.TRAINTIME_API_KEY,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    // Fixed hosts (tests) or, when null, the user's host override read per
    // request so a settings change applies without rebuilding the client. An
    // override is a single host with no failover.
    private val fixedHosts: List<HttpUrl>? = baseUrls?.map { it.toHttpUrl() }
    private val hosts: List<HttpUrl>
        get() = fixedHosts ?: hostOverride.ifEmpty { null }?.let { listOf(it.toHttpUrl()) } ?: HOSTS

    private val failover = HostFailover(hostCount = fixedHosts?.size ?: HOSTS.size, clock = clock)

    // Per-attempt budgets are set on a derived client in attempt(), which
    // shares this one's connection pool.
    private val client = OkHttpClient.Builder()
        .connectTimeout(Timing.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    suspend fun fetchStations(lat: Double, lon: Double, mode: TransportMode? = null): NearbyStations {
        val url = hosts[0].newBuilder()
            .addPathSegments("v1/nearby")
            .addQueryParameter("lat", lat.toString())
            .addQueryParameter("lon", lon.toString())
            .apply { mode?.apiParam?.let { addQueryParameter("mode", it) } }
            .build()
        val body = get(url)
        val dto = json.decodeFromString<NearbyResponseDto>(body)
        val now = clock()
        return NearbyStations(
            train = dto.train.mapNotNull { it.toStation(TransportMode.TRAIN, now) },
            bus = dto.bus.mapNotNull { it.toStation(TransportMode.BUS, now) },
            tram = dto.tram.mapNotNull { it.toStation(TransportMode.TRAM, now) },
            special = dto.special.mapNotNull { it.toStation(TransportMode.SPECIAL, now) },
        )
    }

    suspend fun fetchDepartures(stationId: String, favourites: String? = null): DeparturesResult {
        val url = hosts[0].newBuilder()
            .addPathSegments("v1/departures")
            .addQueryParameter("id", stationId)
            .addQueryParameter("limit", Thresholds.MAX_DEPARTURES.toString())
            .apply { favourites?.let { addQueryParameter("favourites", it) } }
            .build()
        val body = get(url)
        val dto = json.decodeFromString<DeparturesResponseDto>(body)
        val now = clock()
        return DeparturesResult(
            departures = dto.departures.take(Thresholds.MAX_DEPARTURES).map { it.toDeparture(now) }.dedupedForDisplay(),
            favourites = dto.favourites?.map { it.toDeparture(now) }?.dedupedForDisplay() ?: emptyList(),
        )
    }

    suspend fun fetchFormation(
        trainNumber: String,
        date: String,
        stationId: String,
        operatorRef: String? = null,
    ): Formation? {
        val url = hosts[0].newBuilder()
            .addPathSegments("v1/formation")
            .addQueryParameter("train", trainNumber)
            .addQueryParameter("date", date)
            .addQueryParameter("stop", stationId)
            .apply { operatorRef?.let { addQueryParameter("operatorRef", it) } }
            .build()
        return try {
            val body = get(url)
            json.decodeFromString<FormationResponseDto>(body).toFormation()
        } catch (e: TrainApiException) {
            // Formation is best-effort on iOS: any non-200 yields nil.
            null
        }
    }

    // One attempt per host in failover order. A transport error, timeout,
    // 5xx or 429 moves on to the next host, anything else is that host's
    // answer. The last host gets the long budget.
    private suspend fun get(url: HttpUrl): String = withContext(Dispatchers.IO) {
        val hosts = hosts
        if (hosts.size == 1) return@withContext attempt(url, Timing.LAST_ATTEMPT_TIMEOUT_SECONDS)
        val order = failover.order()
        var error: TrainApiException? = null
        for ((attempt, index) in order.withIndex()) {
            if (attempt > 0) ensureActive()
            val host = hosts[index]
            val rehosted = url.newBuilder().scheme(host.scheme).host(host.host).port(host.port).build()
            val last = attempt == order.lastIndex
            val timeout = if (last) Timing.LAST_ATTEMPT_TIMEOUT_SECONDS else Timing.FIRST_ATTEMPT_TIMEOUT_SECONDS
            try {
                return@withContext attempt(rehosted, timeout).also { failover.recordSuccess(index) }
            } catch (e: TrainApiException) {
                if (!e.retriable) {
                    failover.recordSuccess(index)
                    throw e
                }
                failover.recordFailure(index)
                error = e
            }
        }
        throw error!!
    }

    private fun attempt(url: HttpUrl, timeoutSeconds: Long): String {
        val request = Request.Builder()
            .url(url)
            .header("X-API-Key", apiKey)
            .build()
        val call = client.newBuilder()
            .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
            .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
            .build()
            .newCall(request)
        return try {
            call.execute().use {
                when {
                    it.code == 429 -> throw TrainApiException.RateLimited()
                    it.code == 401 -> throw TrainApiException.UpdateRequired()
                    it.code != 200 -> throw TrainApiException.Http(it.code)
                    else -> it.body?.string() ?: throw TrainApiException.NoData()
                }
            }
        } catch (e: IOException) {
            throw TrainApiException.Network()
        }
    }

    companion object {
        // Tried in order. api is the name a load balancer could later sit on,
        // the others are its two backends reached directly.
        val HOSTS: List<HttpUrl> = listOf(
            ApiHost.DEFAULT,
            "https://api1.traintime.ch",
            "https://api2.traintime.ch",
        ).map { it.toHttpUrl() }

        // "" = HOSTS. Written by ApiHost.bind from the saved pref.
        @Volatile var hostOverride: String = ""

        val shared = TrainApi()
    }
}
