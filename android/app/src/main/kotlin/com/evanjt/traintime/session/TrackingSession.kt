package com.evanjt.traintime.session

import com.evanjt.traintime.Thresholds
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.ui.TrackingStatus
import kotlin.math.abs
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow

// Everything the tracking notification renders. Built by the ViewModel while
// the app is foreground (its 10 s fetch is fresher) and by the service's own
// loop while backgrounded, so both paths feed one renderer.
data class TrackingSnapshot(
    val focused: FocusedDeparture,
    val stationId: String?,
    val stationName: String?,
    val stationLat: Double?,
    val stationLon: Double?,
    val walkDistMeters: Double?,
    val gpsOk: Boolean,
    // When tracking began. Survives service restarts via the redelivered
    // start intent.
    val startedEpochSeconds: Long,
)

// The notification's rendition of the in-app TrackingBar, resolution-free:
// the same signed buffer axis (centre = zero margin, ±BAR_SCALE minutes to
// the edges) as coloured runs summing to BAR_UNITS, plus the current
// position. ProgressStyle turns runs into segments; the pre-36 template
// keeps only the position as a plain fill.
enum class BarZone { DARK_GREEN, LIGHT_GREEN, AMBER, DARK_RED, GREY, TRACK }

data class BarRun(val length: Int, val zone: BarZone)

data class BarModel(val runs: List<BarRun>, val position: Int)

// Process-local link between MainViewModel and TrackingNotificationService.
// Both live in this process, so flows beat intents for everything except the
// service's own start/stop lifecycle.
object TrackingSessionBus {
    // Set from the VM's onAppear/onDisappear. The service's loop stays idle
    // while the app is foreground (the VM fetches and pushes instead), and
    // takes over the moment this drops to false.
    val appForeground = MutableStateFlow(false)

    // VM -> service: freshest snapshot to render while foreground.
    val vmPush = MutableSharedFlow<TrackingSnapshot>(extraBufferCapacity = 1)

    // Service -> VM: the notification's "Stop tracking" action. The VM exits
    // tracking so a reopened app doesn't resurrect the session.
    val stopRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
}

// Pure tracking-session rules shared by MainViewModel (in-app) and
// TrackingNotificationService (background). All functions take `now`
// explicitly for testability.
object TrackingLogic {
    // In-app auto-exit threshold: departed more than a minute ago.
    const val DEPARTED_GRACE_SEC = 90L

    // How to run location for a given proximity tier. Accuracy costs battery, and
    // the walk/bar only matter once you're about to walk, so GPS stays off until
    // ~30 min out and only reaches high accuracy near the departure.
    enum class LocationMode { OFF, BALANCED, HIGH }

    // A polling tier chosen by how far the departure is. apiIntervalSec == null
    // means paused: no board fetch, no GPS, the notification lives on the system
    // chronometer alone. This is what makes a next-day tracked trip cost nothing.
    data class PollTier(val apiIntervalSec: Long?, val location: LocationMode)

    // Proximity thresholds (minutes to effective departure), shared with iOS.
    const val TIER_PAUSE_MIN = 360.0 // > 6 h: paused
    const val TIER_FAR_MIN = 60.0 // 1–6 h
    const val TIER_MID_MIN = 30.0 // 30–60 m
    const val TIER_NEAR_MIN = 10.0 // 10–30 m
    const val TIER_CLOSE_MIN = 2.0 // 2–10 m

    fun pollTier(minutesUntil: Double): PollTier = when {
        minutesUntil > TIER_PAUSE_MIN -> PollTier(null, LocationMode.OFF)
        minutesUntil > TIER_FAR_MIN -> PollTier(900, LocationMode.OFF)
        minutesUntil > TIER_MID_MIN -> PollTier(450, LocationMode.OFF)
        minutesUntil > TIER_NEAR_MIN -> PollTier(60, LocationMode.BALANCED)
        minutesUntil > TIER_CLOSE_MIN -> PollTier(30, LocationMode.HIGH)
        else -> PollTier(15, LocationMode.HIGH)
    }

    // The distance-aware "time to leave" moment: due once the effective departure
    // (schedule + delay) is within walk time plus the buffer lead. Fixed-lead
    // callers pass walkMinutes = 0. Latching to fire once is the caller's job.
    fun approachDue(
        focused: FocusedDeparture,
        walkMinutes: Double,
        bufferLeadMinutes: Int,
        nowEpochSeconds: Long,
    ): Boolean {
        val untilEffective = focused.minutesUntil(nowEpochSeconds) + focused.delay
        return untilEffective <= walkMinutes + bufferLeadMinutes && !departed(focused, nowEpochSeconds)
    }

    // Pick the live board row for the tracked departure. Match by train number
    // when there is one (a protected shared-route leg carries it), so live
    // platform/delay are adopted even though the leg's destName is the alight
    // stop. Fall back to destination for board taps that lack a train number.
    fun matchFocused(
        departures: List<Departure>,
        focused: FocusedDeparture,
        nowEpochSeconds: Long,
    ): Departure? {
        val matches = departures.filter {
            (it.destination == focused.destination ||
                (focused.trainNumber != null && it.trainNumber == focused.trainNumber)) &&
                it.minutesUntil >= -1
        }
        return matches.minByOrNull {
            abs(it.minutesUntil.toDouble() - focused.minutesUntil(nowEpochSeconds))
        }
    }

    // Fold a live board row into the tracked departure: platform (with its
    // changed flag), the train's real terminus, and the delay.
    fun adopt(focused: FocusedDeparture, best: Departure): FocusedDeparture {
        var updated = focused
        if (best.platform != focused.platform && best.platform.isNotEmpty()) {
            updated = updated.copy(platform = best.platform, platformChanged = best.platformChanged)
        }
        if (best.destination.isNotEmpty() && best.destination != updated.destination) {
            updated = updated.copy(destination = best.destination)
        }
        return updated.copy(delay = best.delay)
    }

    fun scheduledBuffer(focused: FocusedDeparture, walkMinutes: Double, nowEpochSeconds: Long): Double =
        focused.minutesUntil(nowEpochSeconds) - walkMinutes

    fun effectiveBuffer(focused: FocusedDeparture, walkMinutes: Double, nowEpochSeconds: Long): Double =
        scheduledBuffer(focused, walkMinutes, nowEpochSeconds) + focused.delay.toDouble()

    // A cached or missing coordinate is zero proof of position, so no verdict.
    fun status(effectiveBuffer: Double, gpsOk: Boolean): TrackingStatus = when {
        !gpsOk -> TrackingStatus.NO_GPS
        effectiveBuffer > 0.5 -> TrackingStatus.AHEAD
        effectiveBuffer < -0.5 -> TrackingStatus.BEHIND
        else -> TrackingStatus.ON_TIME
    }

    // A late train has not left. Measure the grace from the effective departure
    // (schedule + delay), or a +3 session would tear itself down while the user
    // is still standing on the platform waiting for it.
    fun departed(focused: FocusedDeparture, nowEpochSeconds: Long): Boolean =
        focused.secondsUntil(nowEpochSeconds) + focused.delay * 60L < -DEPARTED_GRACE_SEC

    const val BAR_UNITS = 1000

    // Mirror of TrackingBar's zone cases. Dark green = guaranteed margin,
    // light green = saved by the delay, amber = recoverable, dark red =
    // irrecoverable, whole bar grey without a usable fix.
    fun barModel(schedBuf: Double, effectBuf: Double, gpsOk: Boolean): BarModel {
        if (!gpsOk) return BarModel(listOf(BarRun(BAR_UNITS, BarZone.GREY)), BAR_UNITS)
        val mid = BAR_UNITS / 2
        fun position(buffer: Double): Int {
            val clamped = buffer.coerceIn(-Thresholds.BAR_SCALE, Thresholds.BAR_SCALE)
            return (mid + (clamped / Thresholds.BAR_SCALE) * mid).toInt()
        }
        val sched = position(schedBuf)
        val effect = position(effectBuf)
        // Interval ends left to right, each with its zone; degenerate
        // intervals drop out below.
        val marks = when {
            schedBuf >= 0 && effectBuf >= 0 -> listOf(
                mid to BarZone.TRACK,
                sched to BarZone.DARK_GREEN,
                effect to BarZone.LIGHT_GREEN,
                BAR_UNITS to BarZone.TRACK,
            )
            schedBuf < 0 && effectBuf < 0 -> listOf(
                sched to BarZone.TRACK,
                effect to BarZone.AMBER,
                mid to BarZone.DARK_RED,
                BAR_UNITS to BarZone.TRACK,
            )
            else -> listOf(
                sched to BarZone.TRACK,
                mid to BarZone.AMBER,
                effect to BarZone.LIGHT_GREEN,
                BAR_UNITS to BarZone.TRACK,
            )
        }
        var prev = 0
        val runs = marks.mapNotNull { (end, zone) ->
            val length = end - prev
            prev = maxOf(prev, end)
            if (length > 0) BarRun(length, zone) else null
        }
        return BarModel(runs, effect)
    }
}
