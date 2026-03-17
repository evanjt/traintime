package ch.traintime.phone.services

import android.content.Context
import ch.traintime.shared.models.FocusedDeparture
import com.garmin.android.connectiq.IQDevice
import org.json.JSONObject

enum class WatchType { GARMIN, WEAR_OS }

data class ConnectedWatch(
    val id: String,
    val name: String,
    val type: WatchType,
    internal val garminDevice: IQDevice? = null,
    internal val wearNodeId: String? = null
)

class WatchService(context: Context) {

    val garminService = GarminService(context)
    private val wearService = WearOSService(context)

    fun initialize() {
        garminService.initialize()
    }

    fun shutdown() {
        garminService.shutdown()
    }

    suspend fun getConnectedWatches(): List<ConnectedWatch> {
        val watches = mutableListOf<ConnectedWatch>()

        // Garmin watches via Connect IQ
        val garminDevices = garminService.getConnectedDevices()
        for ((name, device) in garminDevices) {
            watches.add(
                ConnectedWatch(
                    id = "garmin_${device.deviceIdentifier}",
                    name = name,
                    type = WatchType.GARMIN,
                    garminDevice = device
                )
            )
        }

        // Wear OS watches via Wearable Data Layer
        val wearNodes = wearService.getConnectedNodes()
        for (node in wearNodes) {
            watches.add(
                ConnectedWatch(
                    id = "wear_${node.id}",
                    name = node.displayName,
                    type = WatchType.WEAR_OS,
                    wearNodeId = node.id
                )
            )
        }

        return watches
    }

    suspend fun sendTrackCommand(
        watch: ConnectedWatch,
        departure: FocusedDeparture,
        stationId: String?
    ): Boolean {
        val json = JSONObject().apply {
            put("action", "track")
            put("dest", departure.destination)
            put("depTs", departure.departureTimestamp)
            put("delay", departure.delay)
            put("plat", departure.platform)
            put("platChg", departure.platformChanged)
            if (stationId != null) put("stId", stationId)
        }

        return when (watch.type) {
            WatchType.GARMIN -> {
                val device = watch.garminDevice ?: return false
                // Connect IQ expects a Map, not JSON string
                val data = hashMapOf<String, Any>(
                    "action" to "track",
                    "dest" to departure.destination,
                    "depTs" to departure.departureTimestamp,
                    "delay" to departure.delay,
                    "plat" to departure.platform,
                    "platChg" to departure.platformChanged
                )
                if (stationId != null) data["stId"] = stationId
                garminService.sendMessage(device, data)
            }
            WatchType.WEAR_OS -> {
                val nodeId = watch.wearNodeId ?: return false
                wearService.sendMessage(nodeId, json.toString().toByteArray())
            }
        }
    }
}
