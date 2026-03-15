package ch.traintime.shared.models

import org.json.JSONObject
import java.util.UUID

data class Departure(
    val id: String = UUID.randomUUID().toString(),
    val destination: String,
    val minutesUntil: Int,
    val departureTimestamp: Int?,
    val delay: Int,
    val platform: String,
    val platformChanged: Boolean,
    val lineNumber: String
) {
    companion object {
        fun from(json: JSONObject): Departure {
            val destination = json.optString("to", "?")
            val category = json.optString("category", "")
            val number = json.optString("number", "")
            val lineNumber = if (category in listOf("B", "T", "NFB", "NFT", "M")) number else ""
            val platform = json.optString("platform", "")
            val platformChanged = json.optBoolean("platformChanged", false)

            var minutesUntil = -1
            var depTimestamp: Int? = null
            val now = (System.currentTimeMillis() / 1000).toInt()
            if (json.has("departure")) {
                val depTs = json.getInt("departure")
                depTimestamp = depTs
                minutesUntil = (depTs - now) / 60
            }

            var delay = 0
            val rawDelay = json.optInt("delay", 0)
            if (rawDelay > 0) delay = rawDelay

            return Departure(
                destination = destination,
                minutesUntil = minutesUntil,
                departureTimestamp = depTimestamp,
                delay = delay,
                platform = platform,
                platformChanged = platformChanged,
                lineNumber = lineNumber
            )
        }
    }

    val isGone: Boolean get() = minutesUntil < 0

    val secondsUntil: Int?
        get() {
            val ts = departureTimestamp ?: return null
            return ts - (System.currentTimeMillis() / 1000).toInt()
        }

    val minutesText: String
        get() = when {
            isGone -> "gone"
            minutesUntil == 0 -> "now"
            else -> "$minutesUntil'"
        }
}
