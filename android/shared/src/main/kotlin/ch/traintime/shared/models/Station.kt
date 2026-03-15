package ch.traintime.shared.models

import ch.traintime.shared.Thresholds
import ch.traintime.shared.geo.GeoUtils
import org.json.JSONObject

data class Station(
    val id: String?,
    val name: String?,
    val lat: Double?,
    val lon: Double?,
    val mode: TransportMode,
    val dist: Double?,
    val embeddedDepartures: List<Departure>?
) {
    companion object {
        fun from(json: JSONObject, mode: TransportMode): Station? {
            val id = json.optString("id", null) ?: return null
            val name = json.optString("name", null)
            val lat = if (json.has("lat")) json.getDouble("lat") else null
            val lon = if (json.has("lon")) json.getDouble("lon") else null
            val dist = if (json.has("dist")) json.getDouble("dist") else null

            var embeddedDeps: List<Departure>? = null
            val depsArray = json.optJSONArray("departures")
            if (depsArray != null && depsArray.length() > 0) {
                val deps = mutableListOf<Departure>()
                for (i in 0 until minOf(depsArray.length(), Thresholds.MAX_DEPARTURES)) {
                    deps.add(Departure.from(depsArray.getJSONObject(i)))
                }
                embeddedDeps = deps
            }

            return Station(id, name, lat, lon, mode, dist, embeddedDeps)
        }
    }

    fun walkInfo(index: Int, total: Int): String {
        val d = dist ?: 0.0
        val base = GeoUtils.formatWalkInfo(d)
        return if (total > 1) "$base  ${index + 1}/$total" else base
    }
}
