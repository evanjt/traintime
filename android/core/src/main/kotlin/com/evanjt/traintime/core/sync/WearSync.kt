package com.evanjt.traintime.core.sync

import com.evanjt.traintime.data.model.Favourite
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.sbb.RouteLeg
import com.evanjt.traintime.data.sbb.SharedRoute
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
    // Watch -> phone tracking announcements, riding the liveness path: started
    // carries the full track command (tap-to-follow needs it), ended is bare.
    const val KIND_TRACK_STARTED = "trackStarted"
    const val KIND_TRACK_ENDED = "trackEnded"

    // MessageClient command channel (phone -> watch) for the non-track mirror
    // actions (mode / station / loc / back) matching the Garmin action contract.
    const val CMD_PATH = "/traintime/cmd"

    // MessageClient remind-on-phone command (watch -> phone): the watch asks the
    // phone to save the focused departure as a reminder. A command, not shared
    // state, so it sidesteps the phone-owned pending route on STATE_PATH.
    const val REMINDER_PATH = "/traintime/reminder"

    fun encodeReminder(cmd: ReminderCommand): ByteArray =
        json.encodeToString(cmd).toByteArray(Charsets.UTF_8)

    fun decodeReminder(bytes: ByteArray): ReminderCommand? =
        runCatching { json.decodeFromString<ReminderCommand>(bytes.toString(Charsets.UTF_8)) }.getOrNull()

    // Capability the Wear app declares (res/values/wear.xml). The phone lists only
    // nodes that provide it for Send-to-Watch, so a paired watch without the app
    // installed is not offered a departure it could never receive.
    const val CAPABILITY_WEAR_APP = "traintime_wear_app"

    // Handshake versioning. A watch stamps every liveness announcement with its
    // marketing version (v, for gating + user-facing copy) and this monotonic
    // protocol version (pv). A liveness message with no version field is a
    // pre-versioning build, read as the legacy version 0.4.x.
    // pv 2: hello/alive carry the tracked departure (trk/trkLn) while tracking,
    // and trackStarted/trackEnded ride the liveness path. A phone seeing pv >= 2
    // treats a heartbeat without trk as "not tracking".
    const val PROTOCOL_VERSION = 2
    const val LEGACY_VERSION_NAME = "0.4.x"

    // The only current constraint: the sync features (Send-to-Watch, mirroring)
    // require a watch reporting 0.5.x or higher. A watch below this, or one that
    // reports no version at all, is asked to update. Major.minor only, patch and
    // any "x" placeholder ignored, so "0.5.x" and "0.5.1" both satisfy it.
    const val MIN_SYNC_MAJOR = 0
    const val MIN_SYNC_MINOR = 5

    private fun majorMinor(version: String?): Pair<Int, Int>? {
        val parts = version?.split(".") ?: return null
        if (parts.size < 2) return null
        val major = parts[0].toIntOrNull() ?: return null
        val minor = parts[1].toIntOrNull() ?: return null
        return major to minor
    }

    // True when a watch reporting this version is new enough for the sync
    // features. Null / unparseable (a watch that sent no version) fails.
    fun meetsSyncMinimum(version: String?): Boolean {
        val (major, minor) = majorMinor(version) ?: return false
        return major > MIN_SYNC_MAJOR || (major == MIN_SYNC_MAJOR && minor >= MIN_SYNC_MINOR)
    }

    // The local app's marketing version, set once by each module's Application
    // (:app and :wear read their own BuildConfig.VERSION_NAME). Defaults to the
    // legacy sentinel so an unset build still reports honestly.
    @Volatile
    var localVersionName: String = LEGACY_VERSION_NAME

    val json = Json { ignoreUnknownKeys = true }

    // Encode a liveness announcement stamped with the local version. Always JSON
    // so hello/alive carry v/pv; bye/reqLoc carry them too (harmless). While the
    // watch is tracking, `tracking` mirrors the departure onto hello/alive (and
    // carries the full command on trackStarted, for the phone's tap-to-follow).
    fun encodeLiveness(kind: String, tracking: TrackCommand? = null): String =
        json.encodeToString(
            LivenessMessage(
                kind, localVersionName, PROTOCOL_VERSION,
                trk = tracking?.departureTimestamp,
                trkLn = tracking?.lineNumber,
                track = tracking,
            ),
        )

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

    // Receipt ack for a watch-queued reminder. The watch keeps the reminder in
    // its outbox and retries until it sees this id come back.
    fun garminAckReminderPayload(id: String): Map<String, Any?> =
        mapOf("action" to "ackReminder", "id" to id)

    // Foreground liveness probe; the watch answers with an immediate hello.
    fun garminPingPayload(): Map<String, Any?> =
        mapOf("action" to "ping")

    // Gate for the foreground ping. A phone message can wake a closed Garmin
    // watch-app, so only ping a watch that speaks pv 2 (treats ping as such),
    // hasn't said bye since its last alive, and was heard from recently.
    const val GARMIN_PING_WINDOW_MS = 30_000L

    fun shouldPingGarmin(lastAliveMs: Long, lastByeMs: Long, nowMs: Long, pv: Int): Boolean =
        pv >= 2 && lastAliveMs > lastByeMs && nowMs - lastAliveMs <= GARMIN_PING_WINDOW_MS

    // The phone's favourites, for the Garmin outer-join sync. The watch unions
    // these into its own store (never replaces).
    fun garminFavouritesPayload(favourites: List<Favourite>): Map<String, Any?> =
        mapOf(
            "action" to "favourites",
            "favs" to favourites.map {
                mapOf(
                    "stId" to it.stationId,
                    "name" to it.stationName,
                    "line" to it.lineNumber,
                    "dest" to it.destination,
                )
            },
        )
}

// Watch -> phone liveness announcement over LIVENESS_PATH. Superset of the bare
// kind string: adds the watch's marketing version (v) and protocol version (pv)
// so the phone can gate Send-to-Watch and name the version in "please update".
@Serializable
data class LivenessMessage(
    val kind: String,
    val v: String? = null,
    val pv: Int = 0,
    // pv >= 2: the departure the watch is tracking (depTs + line), stamped on
    // hello/alive while tracking; trackStarted also carries the full command.
    val trk: Long? = null,
    val trkLn: String? = null,
    val track: TrackCommand? = null,
) {
    // True when this watch is new enough (0.5.x+) for the sync features.
    val syncCapable: Boolean get() = WearSync.meetsSyncMinimum(v)

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

// Watch -> phone remind request over REMINDER_PATH. Carries the focused
// departure plus the origin station's id + coords, everything the phone needs to
// synthesise the same one-leg saved route as a board save (SharedRoute.single)
// and schedule its distance-aware reminder. Coords are required: without them the
// leg isn't trackable and no reminder fires.
@Serializable
data class ReminderCommand(
    val destination: String,
    val departureTimestamp: Long,
    val lineNumber: String,
    val trainNumber: String? = null,
    val stationId: String,
    val stationName: String,
    val lat: Double,
    val lon: Double,
) {
    fun toRoute(): SharedRoute = SharedRoute.single(
        originId = stationId,
        originName = stationName,
        originLat = lat,
        originLon = lon,
        destName = destination,
        depTs = departureTimestamp,
        lineNumber = lineNumber,
        trainNumber = trainNumber,
    )
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
    val routeDestination: String? = null,
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
        routeDestination = routeDestination,
    )

    // The Connect IQ phone-app message contract the Garmin watch reads in
    // enterTrackingFromPhone (keys: action/dest/depTs/delay/plat/platChg/line, plus
    // optional cat/trainNum/opRef/stId/routeDest). Matches PhoneWatchService.sendTrackCommand on iOS.
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
        routeDestination?.let { put("routeDest", it) }
    }

    companion object {
        // Build a track command from a saved-route leg, for the reminder's
        // "Send to Watch" action. dest is the leg's alight stop as a best-effort
        // start; the watch's board fetch upgrades it to the train's real terminus
        // via the train-number match. The route's final destination rides in
        // routeDestination so it's shown apart from the terminus, never as it.
        fun fromLeg(leg: RouteLeg, finalDestination: String) = TrackCommand(
            destination = leg.destName,
            departureTimestamp = leg.depTs,
            lineNumber = leg.lineNumber ?: "",
            category = leg.category ?: "",
            trainNumber = leg.trainNumber,
            operatorRef = null,
            delay = 0,
            platform = "",
            platformChanged = false,
            stationId = leg.originId,
            routeDestination = finalDestination,
        )

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
            routeDestination = focused.routeDestination,
        )
    }
}
