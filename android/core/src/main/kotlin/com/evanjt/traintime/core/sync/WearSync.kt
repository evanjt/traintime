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
    // DataClient state item. The analog of WCSession updateApplicationContext.
    const val STATE_PATH = "/traintime/state"
    const val KEY_FAVOURITES = "favourites"
    const val KEY_MY_STATIONS = "myStations"
    const val KEY_DEFAULT_MODE = "defaultMode"
    const val KEY_PENDING_ROUTE = "pendingRoute"

    // MessageClient track command (phone -> watch), like PhoneWatchService.
    const val TRACK_PATH = "/traintime/track"

    // MessageClient liveness announcements (watch -> phone): the same
    // hello/alive/bye kinds the Apple watch sends over WCSession and the Garmin
    // over Connect IQ. Payload is the UTF-8 kind string; "reqLoc" (the watch
    // asking for the phone's location) rides the same path.
    const val LIVENESS_PATH = "/traintime/liveness"
    const val KIND_HELLO = "hello"
    const val KIND_ALIVE = "alive"
    const val KIND_BYE = "bye"
    const val KIND_REQ_LOC = "reqLoc"

    // MessageClient command channel (phone -> watch) for the non-track mirror
    // actions (mode / station / loc / back) matching the Garmin action contract.
    const val CMD_PATH = "/traintime/cmd"

    // Handshake versioning. A watch stamps every liveness announcement with its
    // marketing version (v, for user-facing copy) and this monotonic protocol
    // version (pv, for gating logic). Bump PROTOCOL_VERSION only on a breaking
    // payload change; raise MIN_TRACK_PROTOCOL to refuse Send-to-Watch against a
    // watch too old to understand the current track command. A liveness message
    // with no version field is a pre-versioning build: treated as 0.4.x / pv 0.
    const val PROTOCOL_VERSION = 1
    const val MIN_TRACK_PROTOCOL = 1
    const val LEGACY_VERSION_NAME = "0.4.x"

    // The local app's marketing version, set once by each module's Application
    // (:app and :wear read their own BuildConfig.VERSION_NAME). Defaults to the
    // legacy sentinel so an unset build still reports honestly.
    @Volatile
    var localVersionName: String = LEGACY_VERSION_NAME

    val json = Json { ignoreUnknownKeys = true }

    // Encode a liveness announcement stamped with the local version. Always JSON
    // so hello/alive carry v/pv; bye/reqLoc carry them too (harmless).
    fun encodeLiveness(kind: String): String =
        json.encodeToString(LivenessMessage(kind, localVersionName, PROTOCOL_VERSION))

    // Decode a received liveness announcement. A bare kind string (no JSON) is a
    // pre-versioning watch: reported as the legacy version with pv 0.
    fun decodeLiveness(raw: String): LivenessMessage =
        runCatching { json.decodeFromString<LivenessMessage>(raw) }
            .getOrElse { LivenessMessage(kind = raw, v = LEGACY_VERSION_NAME, pv = 0) }

    fun encodeCommand(cmd: WearCommand): ByteArray =
        json.encodeToString(cmd).toByteArray(Charsets.UTF_8)

    fun decodeCommand(bytes: ByteArray): WearCommand? =
        runCatching { json.decodeFromString<WearCommand>(bytes.toString(Charsets.UTF_8)) }.getOrNull()

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

// Watch -> phone liveness announcement over LIVENESS_PATH. Superset of the bare
// kind string: adds the watch's marketing version (v) and protocol version (pv)
// so the phone can gate Send-to-Watch and name the version in "please update".
@Serializable
data class LivenessMessage(
    val kind: String,
    val v: String? = null,
    val pv: Int = 0,
) {
    // True when this watch is too old to receive the current track command.
    val trackOutdated: Boolean get() = pv < WearSync.MIN_TRACK_PROTOCOL

    // A version string fit for user-facing copy, falling back to the legacy name.
    val displayVersion: String get() = v ?: WearSync.LEGACY_VERSION_NAME
}

// Phone -> watch mirror command over CMD_PATH. Same actions and field names as
// the Garmin phone-app contract (handlePhoneMessage on the Garmin watch).
@Serializable
data class WearCommand(
    val action: String, // "mode" | "station" | "loc" | "back"
    val mode: Int? = null,
    val stId: String? = null,
    val name: String? = null,
    val lat: Double? = null,
    val lon: Double? = null,
)

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
