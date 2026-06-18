package com.evanjt.traintime.data.api

import com.evanjt.traintime.core.BuildConfig
import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.Timing
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

sealed class TrainApiException(message: String) : Exception(message) {
    class RateLimited : TrainApiException("Rate limited")
    class Http(val code: Int) : TrainApiException("HTTP $code")
    class NoData : TrainApiException("No data")
    class Network : TrainApiException("Network error")
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
    baseUrl: String = "https://api.traintime.ch",
    private val apiKey: String = BuildConfig.TRAINTIME_API_KEY,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private val baseUrl: HttpUrl = baseUrl.toHttpUrl()

    private val client = OkHttpClient.Builder()
        .connectTimeout(Timing.REQUEST_TIMEOUT.toLong(), TimeUnit.SECONDS)
        .readTimeout(Timing.REQUEST_TIMEOUT.toLong(), TimeUnit.SECONDS)
        .build()

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    suspend fun fetchStations(lat: Double, lon: Double, mode: TransportMode? = null): NearbyStations {
        val url = baseUrl.newBuilder()
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
        val url = baseUrl.newBuilder()
            .addPathSegments("v1/departures")
            .addQueryParameter("id", stationId)
            .addQueryParameter("limit", Thresholds.MAX_DEPARTURES.toString())
            .apply { favourites?.let { addQueryParameter("favourites", it) } }
            .build()
        val body = get(url)
        val dto = json.decodeFromString<DeparturesResponseDto>(body)
        val now = clock()
        return DeparturesResult(
            departures = dto.departures.take(Thresholds.MAX_DEPARTURES).map { it.toDeparture(now) },
            favourites = dto.favourites?.map { it.toDeparture(now) } ?: emptyList(),
        )
    }

    suspend fun fetchFormation(
        trainNumber: String,
        date: String,
        stationId: String,
        operatorRef: String? = null,
    ): Formation? {
        val url = baseUrl.newBuilder()
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

    private suspend fun get(url: HttpUrl): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(url)
            .header("X-API-Key", apiKey)
            .build()
        val response = try {
            client.newCall(request).execute()
        } catch (e: IOException) {
            throw TrainApiException.Network()
        }
        response.use {
            when {
                it.code == 429 -> throw TrainApiException.RateLimited()
                it.code != 200 -> throw TrainApiException.Http(it.code)
                else -> it.body?.string() ?: throw TrainApiException.NoData()
            }
        }
    }

    companion object {
        val shared = TrainApi()
    }
}
