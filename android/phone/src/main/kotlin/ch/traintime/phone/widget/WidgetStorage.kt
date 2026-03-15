package ch.traintime.phone.widget

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

data class WidgetDeparture(
    val destination: String,
    val departureTimestamp: Int,
    val delay: Int,
    val platform: String,
    val platformChanged: Boolean,
    val lineNumber: String
) {
    val minutesUntil: Int
        get() = (departureTimestamp - (System.currentTimeMillis() / 1000).toInt()) / 60

    val minutesText: String
        get() = when {
            minutesUntil < 0 -> "gone"
            minutesUntil == 0 -> "now"
            else -> "$minutesUntil'"
        }

    val isGone: Boolean get() = minutesUntil < 0
}

data class FetchResult(
    val stationName: String,
    val departures: List<WidgetDeparture>,
    val fetchTime: Double
)

object WidgetStorage {
    private const val PREFS_NAME = "traintime_widget"
    private const val KEY = "widget_fetch_result"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, result: FetchResult) {
        val deps = JSONArray()
        result.departures.forEach { dep ->
            deps.put(JSONObject().apply {
                put("destination", dep.destination)
                put("departureTimestamp", dep.departureTimestamp)
                put("delay", dep.delay)
                put("platform", dep.platform)
                put("platformChanged", dep.platformChanged)
                put("lineNumber", dep.lineNumber)
            })
        }
        val json = JSONObject().apply {
            put("stationName", result.stationName)
            put("departures", deps)
            put("fetchTime", result.fetchTime)
        }
        prefs(context).edit().putString(KEY, json.toString()).apply()
    }

    fun load(context: Context): FetchResult? {
        val raw = prefs(context).getString(KEY, null) ?: return null
        val json = JSONObject(raw)
        val stationName = json.getString("stationName")
        val fetchTime = json.getDouble("fetchTime")
        val depsArray = json.getJSONArray("departures")
        val deps = mutableListOf<WidgetDeparture>()
        for (i in 0 until depsArray.length()) {
            val d = depsArray.getJSONObject(i)
            deps.add(WidgetDeparture(
                destination = d.getString("destination"),
                departureTimestamp = d.getInt("departureTimestamp"),
                delay = d.getInt("delay"),
                platform = d.getString("platform"),
                platformChanged = d.getBoolean("platformChanged"),
                lineNumber = d.getString("lineNumber")
            ))
        }
        return FetchResult(stationName, deps, fetchTime)
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY).apply()
    }
}
