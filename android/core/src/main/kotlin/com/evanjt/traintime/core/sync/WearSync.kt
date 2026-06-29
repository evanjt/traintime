package com.evanjt.traintime.core.sync

import com.evanjt.traintime.data.model.FocusedDeparture
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// Shared Wearable Data Layer contract between :app (phone) and :wear (watch).
// Mirrors the Apple WCSession payloads so the two platforms stay symmetric:
// a persisted state item (favourites / pinned stations / default mode) and a
// fire-and-forget track command.
object WearSync {
    // DataClient state item — the analog of WCSession updateApplicationContext.
    const val STATE_PATH = "/traintime/state"
    const val KEY_FAVOURITES = "favourites"
    const val KEY_MY_STATIONS = "myStations"
    const val KEY_DEFAULT_MODE = "defaultMode"

    // MessageClient track command (phone -> watch), like PhoneWatchService.
    const val TRACK_PATH = "/traintime/track"

    val json = Json { ignoreUnknownKeys = true }

    fun encodeTrack(cmd: TrackCommand): ByteArray =
        json.encodeToString(cmd).toByteArray(Charsets.UTF_8)

    fun decodeTrack(bytes: ByteArray): TrackCommand? =
        runCatching { json.decodeFromString<TrackCommand>(bytes.toString(Charsets.UTF_8)) }.getOrNull()

    fun encodeTrackString(cmd: TrackCommand): String = json.encodeToString(cmd)

    fun decodeTrackString(raw: String): TrackCommand? =
        runCatching { json.decodeFromString<TrackCommand>(raw) }.getOrNull()

    // Connect IQ phone-app payloads for the action-dispatched Garmin contract
    // (handlePhoneMessage on the watch). Track lives on TrackCommand.toGarminMap();
    // these cover the remaining mirror + location-backfill actions.

    // Switch the watch's live mode (0 train / 1 bus / 2 tram).
    fun garminModePayload(mode: Int): Map<String, Any?> =
        mapOf("action" to "mode", "mode" to mode)

    // Show a specific station on the watch.
    fun garminStationPayload(id: String, name: String, lat: Double?, lon: Double?): Map<String, Any?> =
        buildMap {
            put("action", "station")
            put("stId", id)
            put("name", name)
            lat?.let { put("lat", it) }
            lon?.let { put("lon", it) }
        }

    // Phone location used as a GPS fallback when the watch's own signal is weak.
    fun garminLocationPayload(lat: Double, lon: Double): Map<String, Any?> =
        mapOf("action" to "loc", "lat" to lat, "lon" to lon)
}

// The same fields PhoneWatchService.sendMessage carries on iOS. A superset of
// FocusedDeparture plus the originating stationId (so the watch can fetch the
// rail formation).
@Serializable
data class TrackCommand(
    val destination: String,
    val departureTimestamp: Long,
    val lineNumber: String,
    val category: String,
    val trainNumber: String? = null,
    val operatorRef: String? = null,
    val delay: Int = 0,
    val platform: String = "",
    val platformChanged: Boolean = false,
    val stationId: String? = null,
) {
    fun toFocusedDeparture() = FocusedDeparture(
        destination = destination,
        departureTimestamp = departureTimestamp,
        lineNumber = lineNumber,
        category = category,
        trainNumber = trainNumber,
        operatorRef = operatorRef,
        delay = delay,
        platform = platform,
        platformChanged = platformChanged,
    )

    // The Connect IQ phone-app message contract the Garmin watch reads in
    // enterTrackingFromPhone (keys: action/dest/depTs/delay/plat/platChg/line, plus
    // optional cat/trainNum/opRef/stId). Matches PhoneWatchService.sendTrackCommand on iOS.
    fun toGarminMap(): Map<String, Any?> = buildMap {
        put("action", "track")
        put("dest", destination)
        put("depTs", departureTimestamp)
        put("delay", delay)
        put("plat", platform)
        put("platChg", platformChanged)
        put("cat", category)
        put("line", lineNumber)
        trainNumber?.let { put("trainNum", it) }
        operatorRef?.let { put("opRef", it) }
        stationId?.let { put("stId", it) }
    }

    companion object {
        fun from(focused: FocusedDeparture, stationId: String?) = TrackCommand(
            destination = focused.destination,
            departureTimestamp = focused.departureTimestamp,
            lineNumber = focused.lineNumber,
            category = focused.category,
            trainNumber = focused.trainNumber,
            operatorRef = focused.operatorRef,
            delay = focused.delay,
            platform = focused.platform,
            platformChanged = focused.platformChanged,
            stationId = stationId,
        )
    }
}
