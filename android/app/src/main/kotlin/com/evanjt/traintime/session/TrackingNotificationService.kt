package com.evanjt.traintime.session

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.evanjt.traintime.MainActivity
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.core.sync.TrackCommand
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.data.api.TrainApi
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.data.prefs.PendingRouteStore
import com.evanjt.traintime.domain.Fix
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.LocaleUtil
import com.evanjt.traintime.domain.WalkEstimator
import com.evanjt.traintime.ui.TrackingStatus
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString

// Keeps a tracking session alive and visible when the app leaves the
// foreground: a location-typed foreground service (the phone analog of the
// wear TrackingService) owning an ongoing notification with the countdown,
// platform/delay and the walk-vs-departure verdict. The countdown itself is a
// system chronometer, so it ticks correctly even between updates or after
// process death. While the app is foreground the ViewModel pushes fresher
// state over TrackingSessionBus; backgrounded, this service's own loop
// fetches the board and recomputes the walk from its own location updates.
class TrackingNotificationService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Written from the main thread (onStartCommand, the location callback) and
    // read from the loop on Dispatchers.Default, so every shared field is
    // volatile and the fix is one immutable value: reading lat and lon
    // separately could otherwise tear.
    @Volatile private var snapshot: TrackingSnapshot? = null
    @Volatile private var lastFix: TimedFix? = null
    private var loopStarted = false

    // Captured on the monotonic clock; age is derived when the walk is computed.
    private data class TimedFix(val lat: Double, val lon: Double, val elapsedMs: Long)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                TrackingSessionBus.stopRequests.tryEmit(Unit)
                stopSession()
                return START_NOT_STICKY
            }
            else -> {
                val parsed = intent?.let { decodeSnapshot(it) }
                if (parsed == null && snapshot == null) {
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                // A different departure is a fresh session: re-arm the one-shot
                // leave alert. A redelivered identical intent (process death)
                // keeps the latch so it doesn't fire twice.
                parsed?.let {
                    if (it.focused.departureTimestamp != snapshot?.focused?.departureTimestamp) {
                        approachAlerted = intent?.getBooleanExtra(EXTRA_SUPPRESS_ALERT, false) == true
                        approachFired = false
                    }
                    snapshot = it
                }
                val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                } else {
                    0
                }
                try {
                    ServiceCompat.startForeground(this, NOTIF_ID, render(snapshot!!), type)
                } catch (_: Exception) {
                    // Location permission gone between start and here; tracking
                    // stays in-app only.
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                ensureRunning()
            }
        }
        // Redeliver the start intent after a process death, so the session
        // (and its fixed progress axis) is rebuilt without the ViewModel.
        return START_REDELIVER_INTENT
    }

    // Minutes to the effective departure (schedule + delay): the axis the poll
    // tier is chosen on, so a delayed train relaxes the cadence accordingly.
    private fun effectiveMinutes(snap: TrackingSnapshot, nowEpochSeconds: Long): Double =
        snap.focused.minutesUntil(nowEpochSeconds) + snap.focused.delay

    // Loop, location updates and the VM push collector, started once.
    private fun ensureRunning() {
        if (loopStarted) return
        loopStarted = true

        scope.launch {
            TrackingSessionBus.vmPush.collect { fresh ->
                snapshot = fresh
                // Foreground: the VM's own location feeds the walk, so the
                // service holds no fix of its own.
                applyLocationMode(TrackingLogic.LocationMode.OFF)
                pushNotification(fresh)
            }
        }

        // React the moment the app leaves the foreground: bring the tiered
        // location up straight away rather than waiting a full poll interval.
        scope.launch {
            TrackingSessionBus.appForeground.collect { foreground ->
                if (!foreground) snapshot?.let { snap ->
                    // Leaving the immersive screen: lift the start-time suppression so a
                    // backgrounded session still gets its one "time to leave" heads-up,
                    // unless it already fired this session.
                    if (!approachFired) approachAlerted = false
                    val now = System.currentTimeMillis() / 1000
                    applyLocationMode(TrackingLogic.pollTier(effectiveMinutes(snap, now)).location)
                }
            }
        }

        scope.launch {
            var lastPollAt = 0L
            while (isActive) {
                val snap = snapshot
                val now = System.currentTimeMillis() / 1000
                val tier = snap?.let { TrackingLogic.pollTier(effectiveMinutes(it, now)) }
                if (snap != null && tier != null) {
                    // Departed: tear the whole session down. Nothing about a train
                    // that has left is worth a notification, a poll or a fix.
                    if (TrackingLogic.departed(snap.focused, now)) {
                        stopSession()
                        break
                    }
                    // Foreground tracking screen: the VM owns fetching and pushes.
                    if (!TrackingSessionBus.appForeground.value) {
                        applyLocationMode(tier.location)
                        // Paused (very far): no fetch, no GPS — the chronometer
                        // carries the countdown for free until it's worth waking.
                        if (tier.apiIntervalSec != null) {
                            if (now - lastPollAt >= tier.apiIntervalSec) {
                                lastPollAt = now
                                refresh(snap, now)
                                maybeApproachAlert(snapshot ?: snap, now)
                            } else {
                                // Between polls the bar and the ahead/behind
                                // verdict still move with the clock, so redraw
                                // from what we already hold. Costs a render, no
                                // network and no fix.
                                pushNotification(snapshot ?: snap)
                            }
                        }
                    }
                }
                delay((tier?.let { tickSeconds(it) } ?: PAUSED_WAKE_SEC) * 1000)
            }
        }
    }

    // Redraw cadence, deliberately faster than the poll cadence: the board is
    // expensive to fetch but the bar is pure arithmetic on the clock. Matches
    // what the tracking screen shows, which is seconds up close and whole
    // minutes further out.
    private fun tickSeconds(tier: TrackingLogic.PollTier): Long {
        val poll = tier.apiIntervalSec ?: return PAUSED_WAKE_SEC
        return when (tier.location) {
            // GPS off, so there is no walk verdict yet and nothing but the
            // chronometer moves. Waking early would buy nothing.
            TrackingLogic.LocationMode.OFF -> poll
            TrackingLogic.LocationMode.BALANCED -> minOf(poll, 5L)
            TrackingLogic.LocationMode.HIGH -> 1L
        }
    }

    // Background tick: adopt live board data, fold in the freshest fix, render.
    private suspend fun refresh(snap: TrackingSnapshot, now: Long) {
        var focused = snap.focused
        val previousPlatform = focused.platform
        snap.stationId?.let { stationId ->
            runCatching { TrainApi.shared.fetchDepartures(stationId) }.getOrNull()?.let { board ->
                TrackingLogic.matchFocused(board.departures, focused, now)?.let { best ->
                    focused = TrackingLogic.adopt(focused, best)
                }
            }
        }

        // A stale fix still beats no margin: without background location every
        // fix goes stale within minutes, and discarding it would blank the walk
        // rather than fall back to where the user last was.
        val elapsedNow = android.os.SystemClock.elapsedRealtime()
        val estimate = WalkEstimator.estimate(
            fix = lastFix?.let { Fix(it.lat, it.lon, elapsedNow - it.elapsedMs) },
            stationLat = snap.stationLat,
            stationLon = snap.stationLon,
            fallbackMeters = snap.walkDistMeters.takeIf { snap.gpsOk },
        )

        val updated = snap.copy(
            focused = focused,
            walkDistMeters = estimate.distanceMeters,
            gpsOk = estimate.known,
        )
        snapshot = updated

        if (focused.platform != previousPlatform && focused.platformChanged) {
            alertPlatformChange(updated)
        }
        pushNotification(updated)
    }

    // Match the running location request to the proximity tier. High accuracy
    // near the station where the walk/bar matter, balanced (coarse, larger
    // displacement) at the mid tier, and fully off when far or foreground — the
    // biggest battery lever, since GPS is the dominant drain.
    // Synchronized: the loop and the foreground collector both call this, and two
    // concurrent calls could otherwise each register a callback while only the
    // last one is ever removed, leaking location updates for the process's life.
    @Synchronized
    private fun applyLocationMode(mode: TrackingLogic.LocationMode) {
        if (mode == currentLocationMode) return
        currentLocationMode = mode
        val client = LocationServices.getFusedLocationProviderClient(this)
        locationCallback?.let { client.removeLocationUpdates(it) }
        locationCallback = null
        if (mode == TrackingLogic.LocationMode.OFF) return
        val request = when (mode) {
            TrackingLogic.LocationMode.HIGH ->
                LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10_000L)
                    .setMinUpdateDistanceMeters(10f).build()
            else ->
                LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 30_000L)
                    .setMinUpdateDistanceMeters(50f).build()
        }
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                lastFix = TimedFix(
                    loc.latitude,
                    loc.longitude,
                    android.os.SystemClock.elapsedRealtime(),
                )
            }
        }
        locationCallback = callback
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
        } catch (_: SecurityException) {
            // No permission: the bar shows the no-GPS state instead.
        }
    }

    @Volatile private var locationCallback: LocationCallback? = null
    @Volatile private var currentLocationMode: TrackingLogic.LocationMode? = null

    // Fired at most once per session: the distance-aware "time to leave" heads-up.
    // `approachAlerted` also carries the immersive-start suppression, which is lifted
    // on backgrounding; `approachFired` records an actual fire so it isn't re-shown.
    @Volatile private var approachAlerted = false
    @Volatile private var approachFired = false

    // The one-shot leave alert. Distance-aware by default: due once the effective
    // departure is within walk time plus the reminder-lead buffer. Fixed-lead
    // (walk = 0) when distance-aware is off. Uses the freshest walk the tiered
    // location has produced; if none yet (long walk, GPS not on), falls back to
    // the fixed buffer so it still fires.
    private suspend fun maybeApproachAlert(snap: TrackingSnapshot, nowEpochSeconds: Long) {
        if (approachAlerted) return
        // A queued shared route already owns the "leave soon" heads-up through its
        // own reminder (which also survives reboot), so don't double up.
        if (PendingRouteStore(this).current() != null) return
        val prefs = AppPrefs(this)
        if (!prefs.alertBeforeDeparture.first()) return
        val bufferLead = prefs.routeReminderLeadMinutes.first()
        val distanceAware = prefs.distanceAwareReminder.first()
        val walkMin = snap.walkDistMeters?.let { GeoUtils.walkMinutes(it) }
        val walkArg = if (distanceAware) (walkMin ?: 0.0) else 0.0
        if (TrackingLogic.approachDue(snap.focused, walkArg, bufferLead, nowEpochSeconds)) {
            approachAlerted = true
            approachFired = true
            alertApproach(snap)
        }
    }

    private fun alertApproach(snap: TrackingSnapshot) {
        val ctx = localised()
        ensureChannels(ctx)
        // Scheduled time plus a separate "+N", the same way the board reads it.
        val time = HHMM.format(
            Instant.ofEpochSecond(snap.focused.departureTimestamp).atZone(ZoneId.systemDefault()),
        )
        val delay = if (snap.focused.delay > 0) {
            " · " + ctx.getString(R.string.delay_plus_fmt, snap.focused.delay)
        } else {
            ""
        }
        val body = ctx.getString(CoreR.string.leg_places_fmt, snap.focused.lineNumber, snap.focused.destination) +
            " · " + time + delay
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(ctx.getString(R.string.approach_alert_title))
            .setContentText(body)
            .setAutoCancel(true)
            .setTimeoutAfter(alertTimeoutMs(snap))
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(tapIntent(snap))
            .build()
        getSystemService(NotificationManager::class.java).notify(APPROACH_NOTIF_ID, notification)
    }

    // ---- Notification rendering ----

    // Notifications render outside any activity, so resolve strings through a
    // context wrapped in the stored per-app language tag (pre-33 the picker
    // override only reaches activities).
    // Cached: render() now runs as often as once a second, and resolving this
    // blocks on a DataStore read. Dropped on any configuration change, which is
    // where both the language and light/dark live.
    private var localisedCtx: Context? = null

    private fun localised(): Context = localisedCtx ?: run {
        val tag = runBlocking { AppPrefs(this@TrackingNotificationService).appLanguage.first() }
        LocaleUtil.localised(this, tag).also { localisedCtx = it }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        localisedCtx = null
        snapshot?.let { pushNotification(it) }
    }

    private fun render(snap: TrackingSnapshot): Notification {
        val ctx = localised()
        ensureChannels(ctx)
        val now = System.currentTimeMillis() / 1000
        val focused = snap.focused
        val night = isNight()

        val walkMin = snap.walkDistMeters?.let { GeoUtils.walkMinutes(it) }
        val gpsOk = snap.gpsOk && walkMin != null
        val schedBuf = TrackingLogic.scheduledBuffer(focused, walkMin ?: 0.0, now)
        val effectBuf = TrackingLogic.effectiveBuffer(focused, walkMin ?: 0.0, now)
        val status = TrackingLogic.status(effectBuf, gpsOk)
        // Far out we deliberately keep GPS off, so there is no walk verdict yet:
        // show a calm "not near yet" bar and skip the ahead/behind line rather
        // than the no-signal error state. It wakes up as departure approaches.
        val tier = TrackingLogic.pollTier(focused.minutesUntil(now) + focused.delay)
        val awaitingProximity = tier.location == TrackingLogic.LocationMode.OFF && walkMin == null
        val bar = if (awaitingProximity) {
            BarModel(listOf(BarRun(TrackingLogic.BAR_UNITS, BarZone.TRACK)), TrackingLogic.BAR_UNITS / 2)
        } else {
            TrackingLogic.barModel(schedBuf, effectBuf, gpsOk)
        }

        val title = ctx.getString(CoreR.string.leg_places_fmt, focused.lineNumber, focused.destination)
        val dot = when {
            awaitingProximity -> ""
            status == TrackingStatus.AHEAD -> "🟢 "
            status == TrackingStatus.BEHIND -> "🔴 "
            status == TrackingStatus.ON_TIME -> "🟡 "
            else -> ""
        }
        // The verdict is the first thing on the card. OnePlus Fluid Cloud
        // drops contentText but renders subText, so the verdict lives there
        // alongside the timetable facts. contentText carries the walk only.
        val sub = mutableListOf<String>()
        if (awaitingProximity) {
            sub += ctx.getString(R.string.tracking_far)
        } else {
            sub += dot + statusText(ctx, status, effectBuf)
        }
        snap.stationName?.let { sub += it }
        if (focused.platform.isNotEmpty()) sub += ctx.getString(R.string.platform_full_fmt, focused.platform)
        sub += HHMM.format(Instant.ofEpochSecond(focused.departureTimestamp).atZone(ZoneId.systemDefault()))
        if (focused.delay > 0) sub += ctx.getString(R.string.delay_plus_fmt, focused.delay)
        val subText = sub.joinToString(" · ")
        val detail = walkMin?.roundToInt()?.takeIf { it >= 1 }
            ?.let { ctx.getString(R.string.walk_min_fmt, it) } ?: ""
        // Count down to the moment you have to start walking, not to the
        // departure: adjusted departure (schedule + delay) minus the walk. Time
        // until departure is what a timetable app shows; the margin you have
        // left to catch it is what this app is for. It's also the same quantity
        // the bar and the ahead/behind line already draw, so the three surfaces
        // can never disagree.
        // No walk read yet (far out, GPS deliberately off) means no margin to
        // count, so fall back to the scheduled departure the board shows.
        val effectiveDep = focused.departureTimestamp + focused.delay * 60L
        val leaveBySec = if (gpsOk && walkMin != null) {
            effectiveDep - (walkMin * 60).toLong()
        } else {
            effectiveDep
        }
        val departing = now >= effectiveDep

        // Android 16+: a promotable ProgressStyle notification, the only shape the
        // system will promote to a status-bar / OEM-island chip. Promotion needs a
        // promotable style with a title and — verified on-device — NOT colorized:
        // a colorized card never earns FLAG_PROMOTED_ONGOING. A custom RemoteView
        // disqualifies it too, so the gapless bitmap bar can't be promoted; its
        // ahead/behind colours are carried by ProgressStyle segments instead
        // (segmented with hairline gaps, the closest the template allows).
        if (Build.VERSION.SDK_INT >= 36) {
            val progress = NotificationCompat.ProgressStyle()
                .setProgress(bar.position)
                // This is the app's diverging ahead/behind axis, NOT progress
                // toward departure: centre is zero margin and the colour runs
                // out from it. Styled-by-progress (the default) fades everything
                // past the progress point, which erased the dark-red "won't make
                // it" region entirely and flattened the two greens into one.
                .setStyledByProgress(false)
                .setProgressSegments(
                    bar.runs.map {
                        NotificationCompat.ProgressStyle.Segment(it.length).setColor(segmentColor(it.zone, night))
                    },
                )
                // No centre point: the template draws one as a fat square that
                // breaks the bar, and the centre is already where the colour
                // starts (ahead) or ends (behind), so it needs no marker.
            val stopLabel = ctx.getString(R.string.stop_tracking)
            val b = NotificationCompat.Builder(this, CHIP_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notif_traintime)
                .setContentTitle(title)
                .setContentText(detail)
                .setStyle(progress)
                .setColor(verdictColor(status, awaitingProximity))
                .setColorized(false)
                .setSubText(subText)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setRequestPromotedOngoing(true)
                .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
                .setContentIntent(tapIntent(snap))
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, stopLabel, stopIntent())
            // The chip's countdown is a system chronometer that ticks to the
            // leave-by moment (schedule + delay - walk). Positive = margin left,
            // zero = leave now. It ticks per second natively, for free. Setting
            // shortCriticalText overrides it and can only update at our render
            // rate (5 s at BALANCED), so we only set it when there's no margin
            // to count: far out with no GPS, or after departure.
            val clock = HHMM.format(
                Instant.ofEpochSecond(focused.departureTimestamp).atZone(ZoneId.systemDefault()),
            )
            // Countdown to the leave-by moment. Once it's passed but the train
            // hasn't gone, count negative: the chip then says how far behind the
            // walk you are, the same margin the bar and ahead/behind line show.
            val leaveByDelta = leaveBySec - now
            fun ms(s: Long) = String.format("%d:%02d", s / 60, s % 60)
            // Only where the chronometer has nothing useful to show: after
            // departure, and once the leave-by moment has passed (a countdown
            // past zero is not reliably rendered as negative). Setting it while
            // there is still margin freezes the chip at our render rate, and on
            // the paused tier we don't render at all.
            when {
                departing -> b.setShortCriticalText(clock)
                leaveByDelta < 0 -> b.setShortCriticalText("-" + ms(-leaveByDelta))
            }
            if (departing) {
                // Past the departure: freeze rather than counting into the
                // negatives. A delayed train keeps its card until it really goes.
                b.setShowWhen(false)
            } else {
                b.setWhen(leaveBySec * 1000).setShowWhen(true)
                    .setUsesChronometer(true).setChronometerCountDown(true)
            }
            return b.build()
        }

        // Pre-16: the custom gapless diverging bar. No promotion exists on these
        // versions, so the RemoteView bitmap renders our exact multi-colour bar.
        // DecoratedCustomViewStyle keeps the system header, the countdown
        // chronometer and the Stop action; we own only the strip.
        val barBmp = renderBarBitmap(bar, night)
        // Countdown ticks system-side (elapsedRealtime base), so it keeps
        // running with the app suspended. Counts to the same leave-by moment as
        // the 16+ card. Once the train is at/past departure, freeze it at 0:00
        // rather than counting into the negatives; the departed teardown
        // replaces the card within the grace window.
        val countdownBase = android.os.SystemClock.elapsedRealtime() +
            (leaveBySec * 1000 - System.currentTimeMillis())
        fun RemoteViews.fillCommon(): RemoteViews = apply {
            setTextViewText(R.id.notif_title, title)
            setTextViewText(R.id.notif_detail, detail)
            setImageViewBitmap(R.id.notif_bar, barBmp)
            setChronometerCountDown(R.id.notif_countdown, true)
            setChronometer(
                R.id.notif_countdown,
                if (departing) android.os.SystemClock.elapsedRealtime() else countdownBase,
                null,
                !departing,
            )
        }
        val stopLabel = ctx.getString(R.string.stop_tracking)
        // Collapsed carries a compact chip-styled Stop (actions never show
        // collapsed); expanded gets the full "Stop tracking" system action row.
        val collapsed = RemoteViews(packageName, R.layout.notif_tracking).fillCommon().apply {
            setTextViewText(R.id.notif_stop, ctx.getString(R.string.stop_short))
            setContentDescription(R.id.notif_stop, stopLabel)
            setOnClickPendingIntent(R.id.notif_stop, stopIntent())
        }
        val expanded = RemoteViews(packageName, R.layout.notif_tracking_big).fillCommon()

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(title)
            .setContentText(detail)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setSubText(subText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setShowWhen(false)
            .setContentIntent(tapIntent(snap))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, stopLabel, stopIntent())
            .build()
    }

    // Card colour by walk verdict: green ahead, amber on time, red behind,
    // grey when there's no walk read yet (far, GPS still off). Drives the
    // header/icon accent on Android 16+ (the card itself can't be colorized
    // without losing promotion).
    private fun verdictColor(status: TrackingStatus, awaiting: Boolean): Int = when {
        awaiting -> 0xFF6B7076.toInt()
        status == TrackingStatus.AHEAD -> 0xFF1E8E3E.toInt()
        status == TrackingStatus.BEHIND -> 0xFFD32F2F.toInt()
        status == TrackingStatus.ON_TIME -> 0xFFE08A00.toInt()
        else -> 0xFF6B7076.toInt()
    }

    // Render the tracking-bar model as a small ARGB bitmap: contiguous coloured
    // runs across the buffer axis with rounded ends and a faint centre hairline,
    // matching the in-app TrackingBar. fitXY stretches it to the notification
    // width, so the modest fixed size stays well under the ~1 MB RemoteViews
    // transaction budget.
    private fun renderBarBitmap(bar: BarModel, night: Boolean): Bitmap {
        val w = BAR_BMP_W
        val h = BAR_BMP_H
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = h * 0.4f
        canvas.clipPath(Path().apply {
            addRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, Path.Direction.CW)
        })
        var x = 0f
        val unit = w.toFloat() / TrackingLogic.BAR_UNITS
        for (run in bar.runs) {
            paint.color = zoneColor(run.zone, night)
            val next = x + run.length * unit
            canvas.drawRect(x, 0f, next, h.toFloat(), paint)
            x = next
        }
        // Centre marker: the zero-margin hairline, subtle like the in-app bar.
        paint.color = centreColor(night)
        val cx = w / 2f
        val half = w * 0.005f
        canvas.drawRect(cx - half, 0f, cx + half, h.toFloat(), paint)
        return bmp
    }

    // LightPalette/DarkPalette verbatim, so the bitmap bar reads exactly like
    // the tracking screen: dark green = guaranteed margin, light green = margin
    // owed to the delay, amber = recoverable, dark red = irrecoverable. We draw
    // this one ourselves, so the colours arrive on screen untouched.
    // A notification follows the SYSTEM theme rather than the app's, so the
    // light/dark pair is chosen per render from the config.
    private fun zoneColor(zone: BarZone, night: Boolean): Int = when (zone) {
        BarZone.DARK_GREEN -> if (night) 0xFF00FF00.toInt() else 0xFF1E8E3E.toInt()
        BarZone.LIGHT_GREEN -> if (night) 0xFF55FF55.toInt() else 0xFF6FCF82.toInt()
        BarZone.AMBER -> if (night) 0xFFFFAA00.toInt() else 0xFFE08A00.toInt()
        BarZone.DARK_RED -> if (night) 0xFFFF0000.toInt() else 0xFFD32F2F.toInt()
        BarZone.GREY -> if (night) 0xFF444444.toInt() else 0xFFC7C7CC.toInt()
        // The empty axis. The app draws it as the screen background, which on a
        // notification card would vanish, so it sits a hair off the card instead.
        BarZone.TRACK -> if (night) 0xFF2E3238.toInt() else 0xFFE5E5EA.toInt()
    }

    // ProgressStyle repaints every segment we hand it: sanitizeProgressColor()
    // forces each one to at least 3:1 against the card background, keeping the
    // hue but dragging the lightness. Passing the app palette through that
    // flattened both greens onto the same darkness and turned the near-white
    // empty axis into mid-grey, which is why the card stopped matching the
    // screen. So this palette is pre-cleared: every colour already sits above
    // the floor, the platform leaves it alone, and the two greens stay apart on
    // the only axis left (darker-than in light mode, lighter-than in dark).
    private fun segmentColor(zone: BarZone, night: Boolean): Int = when (zone) {
        BarZone.DARK_GREEN -> if (night) 0xFF1F9D4A.toInt() else 0xFF0B5D24.toInt()
        BarZone.LIGHT_GREEN -> if (night) 0xFFA8F0BC.toInt() else 0xFF448C5C.toInt()
        BarZone.AMBER -> if (night) 0xFFFFB020.toInt() else 0xFFB36B00.toInt()
        BarZone.DARK_RED -> if (night) 0xFFFF6B60.toInt() else 0xFFA3231B.toInt()
        BarZone.GREY -> if (night) 0xFF8A9099.toInt() else 0xFF6E7175.toInt()
        BarZone.TRACK -> if (night) 0xFF6E7276.toInt() else 0xFF7E7F83.toInt()
    }

    // The app's zero-margin hairline: barGray at 80%, over the empty axis.
    private fun centreColor(night: Boolean): Int =
        if (night) 0xCC444444.toInt() else 0xCCC7C7CC.toInt()

    // Notifications render in the system's theme, not the app's chosen one.
    private fun isNight(): Boolean =
        resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES

    private fun statusText(ctx: Context, status: TrackingStatus, effectBuf: Double): String {
        if (status == TrackingStatus.NO_GPS) return ctx.getString(CoreR.string.no_gps)
        val absBuf = kotlin.math.abs(effectBuf)
        if (absBuf < 0.5) return ctx.getString(CoreR.string.on_time)
        val unit = if (absBuf < 1.5) {
            ctx.getString(CoreR.string.buf_sec_fmt, (absBuf * 60).toInt())
        } else {
            ctx.getString(CoreR.string.buf_min_fmt, absBuf.toInt())
        }
        return if (effectBuf > 0) {
            ctx.getString(CoreR.string.ahead_fmt, unit)
        } else {
            ctx.getString(CoreR.string.behind_fmt, unit)
        }
    }

    private fun tapIntent(snap: TrackingSnapshot): PendingIntent {
        val uri = Uri.Builder()
            .scheme("traintime")
            .authority("track")
            .appendQueryParameter("destination", snap.focused.destination)
            .appendQueryParameter("timestamp", snap.focused.departureTimestamp.toString())
            .build()
        return PendingIntent.getActivity(
            this,
            0,
            Intent(Intent.ACTION_VIEW, uri, this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopIntent(): PendingIntent = PendingIntent.getService(
        this,
        1,
        Intent(this, TrackingNotificationService::class.java).setAction(ACTION_STOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun notifySilently(notification: Notification) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification)
    }

    // On 16+ render() itself is the promoted card; below 16 it's the gradient
    // bar. Either way it's the single foreground-service notification.
    private fun pushNotification(snap: TrackingSnapshot) {
        notifySilently(render(snap))
    }

    // One-shot heads-up on the alert channel, mirroring the in-app double
    // pulse when the platform changes mid-session.
    private fun alertPlatformChange(snap: TrackingSnapshot) {
        val ctx = localised()
        ensureChannels(ctx)
        val body = ctx.getString(CoreR.string.leg_places_fmt, snap.focused.lineNumber, snap.focused.destination) +
            " · " + ctx.getString(R.string.platform_full_fmt, snap.focused.platform)
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(ctx.getString(R.string.platform_change_title))
            .setContentText(body)
            .setAutoCancel(true)
            .setTimeoutAfter(alertTimeoutMs(snap))
            .setContentIntent(tapIntent(snap))
            .build()
        getSystemService(NotificationManager::class.java).notify(ALERT_NOTIF_ID, notification)
    }

    // How long a one-shot alert stays useful: until the train leaves, plus the
    // session's own grace. onDestroy clears them on every ordinary teardown, but
    // an OEM-killed process never gets there, so the system expires them for us.
    private fun alertTimeoutMs(snap: TrackingSnapshot): Long {
        val effectiveDep = snap.focused.departureTimestamp + snap.focused.delay * 60L
        val remaining = (effectiveDep + TrackingLogic.DEPARTED_GRACE_SEC) * 1000 - System.currentTimeMillis()
        return remaining.coerceAtLeast(ALERT_MIN_TIMEOUT_MS)
    }

    private fun stopSession() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        locationCallback?.let {
            LocationServices.getFusedLocationProviderClient(this).removeLocationUpdates(it)
        }
        // Every teardown path lands here (departed, in-app stop, notification
        // Stop), and the one-shot alerts are only about catching this train, so
        // they end with the session rather than sitting in the shade for days.
        getSystemService(NotificationManager::class.java).let {
            it.cancel(ALERT_NOTIF_ID)
            it.cancel(APPROACH_NOTIF_ID)
        }
        scope.cancel()
        super.onDestroy()
    }

    private fun ensureChannels(ctx: Context) {
        val manager = getSystemService(NotificationManager::class.java)
        // The tracking card. On 16+ it must be non-silent (DEFAULT) or the system
        // sweeps it into the collapsed "silent" section and never promotes it to
        // a chip; sound off keeps it a quiet, glanceable navigation card. Below
        // 16 there's no promotion, so a silent LOW channel keeps the bar quiet.
        if (Build.VERSION.SDK_INT >= 36) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHIP_CHANNEL_ID,
                    ctx.getString(R.string.live_tracking_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                },
            )
            // Retire the old LOW tracking channel so it doesn't linger as a
            // duplicate "Live tracking" entry in settings.
            manager.deleteNotificationChannel(CHANNEL_ID)
        } else {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    ctx.getString(R.string.live_tracking_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                ctx.getString(R.string.tracking_alert_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    private fun decodeSnapshot(intent: Intent): TrackingSnapshot? {
        val json = intent.getStringExtra(EXTRA_CMD) ?: return null
        val cmd = runCatching { WearSync.json.decodeFromString<TrackCommand>(json) }.getOrNull() ?: return null
        val lat = intent.getDoubleExtra(EXTRA_STATION_LAT, Double.NaN)
        val lon = intent.getDoubleExtra(EXTRA_STATION_LON, Double.NaN)
        val walk = intent.getDoubleExtra(EXTRA_WALK_DIST, Double.NaN)
        return TrackingSnapshot(
            focused = cmd.toFocusedDeparture(),
            stationId = cmd.stationId,
            stationName = intent.getStringExtra(EXTRA_STATION_NAME),
            stationLat = lat.takeIf { !it.isNaN() },
            stationLon = lon.takeIf { !it.isNaN() },
            walkDistMeters = walk.takeIf { !it.isNaN() },
            gpsOk = intent.getBooleanExtra(EXTRA_GPS_OK, false),
            startedEpochSeconds = intent.getLongExtra(EXTRA_STARTED, System.currentTimeMillis() / 1000),
        )
    }

    companion object {
        // Centre-of-axis hairline: a faint grey just above the empty-track
        // colour, the notification's version of the in-app bar's centre marker.
        private val BAR_CENTRE = 0xFF565A61.toInt()

        // Bar bitmap source size. fitXY stretches it to the row, so this is only
        // the drawing resolution; kept small to stay well under the RemoteViews
        // transaction budget (720x30 ARGB ≈ 86 KB).
        private const val BAR_BMP_W = 720
        private const val BAR_BMP_H = 30

        private val HHMM = DateTimeFormatter.ofPattern("HH:mm")

        private const val CHANNEL_ID = "live_tracking"
        private const val CHIP_CHANNEL_ID = "live_tracking_chip"
        private const val ALERT_CHANNEL_ID = "tracking_alerts"
        private const val NOTIF_ID = 3
        private const val ALERT_NOTIF_ID = 4
        private const val APPROACH_NOTIF_ID = 5
        // How long to sleep between wakes on the paused (> 6 h) tier: no fetch,
        // no GPS, just a periodic clock check to notice the departure nearing.
        private const val PAUSED_WAKE_SEC = 300L

        // Floor for a one-shot alert's self-expiry, so an alert fired right on
        // top of the departure is still readable before it clears.
        private const val ALERT_MIN_TIMEOUT_MS = 60_000L

        const val ACTION_STOP = "com.evanjt.traintime.session.STOP"
        private const val EXTRA_CMD = "cmd"
        private const val EXTRA_STATION_NAME = "stationName"
        private const val EXTRA_STATION_LAT = "stationLat"
        private const val EXTRA_STATION_LON = "stationLon"
        private const val EXTRA_WALK_DIST = "walkDist"
        private const val EXTRA_GPS_OK = "gpsOk"
        private const val EXTRA_STARTED = "started"
        private const val EXTRA_SUPPRESS_ALERT = "suppress_alert"

        fun start(context: Context, snapshot: TrackingSnapshot, suppressApproachAlert: Boolean = false) {
            val intent = Intent(context, TrackingNotificationService::class.java)
                .putExtra(EXTRA_CMD, WearSync.json.encodeToString(TrackCommand.from(snapshot.focused, snapshot.stationId)))
                .putExtra(EXTRA_STATION_NAME, snapshot.stationName)
                .putExtra(EXTRA_STARTED, snapshot.startedEpochSeconds)
                .putExtra(EXTRA_GPS_OK, snapshot.gpsOk)
                .putExtra(EXTRA_SUPPRESS_ALERT, suppressApproachAlert)
            snapshot.stationLat?.let { intent.putExtra(EXTRA_STATION_LAT, it) }
            snapshot.stationLon?.let { intent.putExtra(EXTRA_STATION_LON, it) }
            snapshot.walkDistMeters?.let { intent.putExtra(EXTRA_WALK_DIST, it) }
            runCatching { ContextCompat.startForegroundService(context, intent) }
        }

        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, TrackingNotificationService::class.java)) }
        }
    }
}
