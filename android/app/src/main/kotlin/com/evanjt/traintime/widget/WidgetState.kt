package com.evanjt.traintime.widget

import android.content.Context
import androidx.datastore.core.CorruptionException
import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import androidx.datastore.dataStoreFile
import androidx.glance.state.GlanceStateDefinition
import com.evanjt.traintime.data.model.TransportMode
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import kotlinx.coroutines.flow.first
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// Port of WidgetEntry.swift / WidgetStorage. One snapshot shared by all
// widget instances, mirroring the iOS widget_fetch_result_v2 blob.

@Serializable
data class WidgetDeparture(
    val destination: String,
    val departureTimestamp: Long,
    val delay: Int,
    val platform: String,
    val platformChanged: Boolean,
    val lineNumber: String,
) {
    fun minutesUntil(nowEpochSeconds: Long): Int =
        ((departureTimestamp - nowEpochSeconds) / 60).toInt()

    fun minutesText(nowEpochSeconds: Long): String {
        val m = minutesUntil(nowEpochSeconds)
        return when {
            m < 0 -> "gone"
            m == 0 -> "now"
            else -> "$m'"
        }
    }

    fun isGone(nowEpochSeconds: Long): Boolean = minutesUntil(nowEpochSeconds) < 0

    // Absolute clock time, shown in the dormant view where a stale minute count misleads.
    val clockTimeText: String
        get() {
            val time = java.time.Instant.ofEpochSecond(departureTimestamp)
                .atZone(java.time.ZoneId.systemDefault())
            return "%02d:%02d".format(time.hour, time.minute)
        }

    val favKey: String get() = "$lineNumber|$destination"
}

@Serializable
data class WidgetStation(
    val id: String,
    val name: String,
    val departures: List<WidgetDeparture>,
)

@Serializable
data class WidgetFetchResult(
    val train: List<WidgetStation> = emptyList(),
    val bus: List<WidgetStation> = emptyList(),
    val tram: List<WidgetStation> = emptyList(),
    val special: List<WidgetStation> = emptyList(),
    val selectedModeRaw: Int = 0,
    val selectedStationIndex: Int = 0,
    val fetchTime: Long = 0, // epoch seconds
) {
    val selectedMode: TransportMode get() = TransportMode.fromRaw(selectedModeRaw)

    val availableModes: List<TransportMode>
        get() = buildList {
            if (train.isNotEmpty()) add(TransportMode.TRAIN)
            if (bus.isNotEmpty()) add(TransportMode.BUS)
            if (tram.isNotEmpty()) add(TransportMode.TRAM)
            if (special.isNotEmpty()) add(TransportMode.SPECIAL)
        }

    fun stations(mode: TransportMode): List<WidgetStation> = when (mode) {
        TransportMode.TRAIN -> train
        TransportMode.BUS -> bus
        TransportMode.TRAM -> tram
        TransportMode.SPECIAL -> special
    }

    val currentStation: WidgetStation?
        get() {
            val stns = stations(selectedMode)
            if (stns.isEmpty()) return null
            return stns[selectedStationIndex.coerceAtMost(stns.size - 1)]
        }

    fun withSelection(modeRaw: Int, stationIndex: Int): WidgetFetchResult =
        copy(selectedModeRaw = modeRaw, selectedStationIndex = stationIndex)

    fun withStation(mode: TransportMode, index: Int, station: WidgetStation): WidgetFetchResult =
        when (mode) {
            TransportMode.TRAIN -> copy(train = train.toMutableList().also { it[index] = station })
            TransportMode.BUS -> copy(bus = bus.toMutableList().also { it[index] = station })
            TransportMode.TRAM -> copy(tram = tram.toMutableList().also { it[index] = station })
            TransportMode.SPECIAL -> copy(special = special.toMutableList().also { it[index] = station })
        }
}

// `dormant` is set by the revert/stop worker: rendering is time-dependent
// but recomposition only happens on a state CHANGE, so dormancy must be
// a state transition, not just an age check at render time. `hideFavourites`
// is the grouping toggle — favourites first vs pure time order.
// `refreshStartedAt` drives the refresh control's loading state; it's a
// timestamp (epoch seconds) so a refresh killed mid-flight self-heals after
// 15 s instead of leaving the control stuck on the spinner.
@Serializable
data class WidgetState(
    val result: WidgetFetchResult? = null,
    val refreshStartedAt: Long = 0,
    val dormant: Boolean = false,
    val hideFavourites: Boolean = false,
) {
    fun isRefreshing(nowEpochSeconds: Long): Boolean =
        refreshStartedAt > 0 && nowEpochSeconds - refreshStartedAt < 15
}

// Favourite extraction for the widget. Operates on WidgetDeparture, sourced
// from FavouritesStore favourite keys ("line|destination") for the station.
object WidgetFavourites {
    // One not-yet-gone departure per favourite key, time-ordered — the top block.
    fun block(departures: List<WidgetDeparture>, favKeys: Set<String>, now: Long): List<WidgetDeparture> {
        if (favKeys.isEmpty()) return emptyList()
        val seen = mutableSetOf<String>()
        return departures
            .filter { !it.isGone(now) && it.favKey in favKeys && seen.add(it.favKey) }
            .sortedBy { it.departureTimestamp }
    }
}

private object WidgetStateSerializer : Serializer<WidgetState> {
    private val json = Json { ignoreUnknownKeys = true }

    override val defaultValue = WidgetState()

    override suspend fun readFrom(input: InputStream): WidgetState =
        try {
            json.decodeFromString<WidgetState>(input.readBytes().decodeToString())
        } catch (e: SerializationException) {
            throw CorruptionException("widget state unreadable", e)
        }

    override suspend fun writeTo(t: WidgetState, output: OutputStream) {
        output.write(json.encodeToString(t).encodeToByteArray())
    }
}

// All widget instances share one state file (the iOS widgets share one
// UserDefaults blob the same way), so fileKey is deliberately ignored.
object WidgetStateDefinition : GlanceStateDefinition<WidgetState> {
    private const val FILE_NAME = "traintime_widget_state.json"

    @Volatile
    private var instance: DataStore<WidgetState>? = null

    private fun store(context: Context): DataStore<WidgetState> =
        instance ?: synchronized(this) {
            instance ?: DataStoreFactory.create(
                serializer = WidgetStateSerializer,
                corruptionHandler = androidx.datastore.core.handlers.ReplaceFileCorruptionHandler { WidgetState() },
                produceFile = { context.applicationContext.dataStoreFile(FILE_NAME) },
            ).also { instance = it }
        }

    override suspend fun getDataStore(context: Context, fileKey: String): DataStore<WidgetState> =
        store(context)

    override fun getLocation(context: Context, fileKey: String): File =
        context.applicationContext.dataStoreFile(FILE_NAME)

    suspend fun read(context: Context): WidgetState =
        store(context).data.first()

    suspend fun update(context: Context, transform: (WidgetState) -> WidgetState): WidgetState =
        store(context).updateData { transform(it) }
}
