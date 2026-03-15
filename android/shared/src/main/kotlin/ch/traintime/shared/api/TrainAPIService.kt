package ch.traintime.shared.api

import ch.traintime.shared.Thresholds
import ch.traintime.shared.models.Departure
import ch.traintime.shared.models.Station
import ch.traintime.shared.models.TransportMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

sealed class TrainAPIError : Exception() {
    object RateLimited : TrainAPIError()
    data class HttpError(val code: Int) : TrainAPIError()
    object NoData : TrainAPIError()
    object NetworkError : TrainAPIError()
}

data class StationResult(
    val train: List<Station>,
    val bus: List<Station>,
    val tram: List<Station>,
    val special: List<Station>
)

object TrainAPIService {
    private const val BASE_URL = "https://api.traintime.ch"
    private val apiKey: String get() = Secrets.apiKey

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    suspend fun fetchStations(lat: Double, lon: Double): StationResult = withContext(Dispatchers.IO) {
        val url = "$BASE_URL/v1/nearby?lat=$lat&lon=$lon"
        val json = makeRequest(url)

        StationResult(
            train = parseStationGroup(json.optJSONArray("train"), TransportMode.TRAIN),
            bus = parseStationGroup(json.optJSONArray("bus"), TransportMode.BUS),
            tram = parseStationGroup(json.optJSONArray("tram"), TransportMode.TRAM),
            special = parseStationGroup(json.optJSONArray("special"), TransportMode.SPECIAL)
        )
    }

    suspend fun fetchDepartures(stationId: String): List<Departure> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(stationId, "UTF-8")
        val url = "$BASE_URL/v1/departures?id=$encoded&limit=${Thresholds.MAX_DEPARTURES}"
        val json = makeRequest(url)

        val array = json.optJSONArray("departures") ?: return@withContext emptyList()
        val deps = mutableListOf<Departure>()
        for (i in 0 until minOf(array.length(), Thresholds.MAX_DEPARTURES)) {
            deps.add(Departure.from(array.getJSONObject(i)))
        }
        deps
    }

    private fun parseStationGroup(array: org.json.JSONArray?, mode: TransportMode): List<Station> {
        if (array == null) return emptyList()
        val stations = mutableListOf<Station>()
        for (i in 0 until array.length()) {
            Station.from(array.getJSONObject(i), mode)?.let { stations.add(it) }
        }
        return stations
    }

    private fun makeRequest(url: String): JSONObject {
        val request = Request.Builder()
            .url(url)
            .addHeader("X-API-Key", apiKey)
            .build()

        val response = try {
            client.newCall(request).execute()
        } catch (e: IOException) {
            throw TrainAPIError.NetworkError
        }

        response.use { resp ->
            if (resp.code == 429) throw TrainAPIError.RateLimited
            if (resp.code != 200) throw TrainAPIError.HttpError(resp.code)
            val body = resp.body?.string() ?: throw TrainAPIError.NoData
            return JSONObject(body)
        }
    }
}
