package com.evanjt.traintime.session

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
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
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.domain.LocaleUtil
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
    private var snapshot: TrackingSnapshot? = null
    private var lastFixLat: Double? = null
    private var lastFixLon: Double? = null
    private var lastFixElapsed: Long = 0
    private var loopStarted = false

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
                        approachAlerted = false
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
                updateCompanion(snapshot!!)
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
                    val now = System.currentTimeMillis() / 1000
                    applyLocationMode(TrackingLogic.pollTier(effectiveMinutes(snap, now)).location)
                }
            }
        }

        scope.launch {
            while (isActive) {
                val snap = snapshot
                val now = System.currentTimeMillis() / 1000
                val tier = snap?.let { TrackingLogic.pollTier(effectiveMinutes(it, now)) }
                if (snap != null) {
                    if (TrackingLogic.departed(snap.focused, now)) {
                        finishDeparted(snap)
                        break
                    }
                    // Foreground: the VM owns fetching and pushes over the bus.
                    if (!TrackingSessionBus.appForeground.value) {
                        applyLocationMode(tier!!.location)
                        // Paused (very far): no fetch, no GPS — the chronometer
                        // carries the countdown for free until it's worth waking.
                        if (tier.apiIntervalSec != null) {
                            refresh(snap, now)
                            maybeApproachAlert(snapshot ?: snap, now)
                        }
                    }
                }
                delay((tier?.apiIntervalSec ?: PAUSED_WAKE_SEC) * 1000)
            }
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

        val fixFresh = lastFixLat != null &&
            android.os.SystemClock.elapsedRealtime() - lastFixElapsed < FIX_MAX_AGE_MS
        val walk = if (fixFresh && snap.stationLat != null && snap.stationLon != null) {
            GeoUtils.haversineDistance(lastFixLat!!, lastFixLon!!, snap.stationLat, snap.stationLon)
        } else {
            snap.walkDistMeters.takeIf { snap.gpsOk }
        }

        val updated = snap.copy(focused = focused, walkDistMeters = walk, gpsOk = fixFresh || (snap.gpsOk && walk != null))
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
                lastFixLat = loc.latitude
                lastFixLon = loc.longitude
                lastFixElapsed = android.os.SystemClock.elapsedRealtime()
            }
        }
        locationCallback = callback
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
        } catch (_: SecurityException) {
            // No permission: the bar shows the no-GPS state instead.
        }
    }

    private var locationCallback: LocationCallback? = null
    private var currentLocationMode: TrackingLogic.LocationMode? = null

    // Fired at most once per session: the distance-aware "time to leave" heads-up.
    private var approachAlerted = false

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
            alertApproach(snap)
        }
    }

    private fun alertApproach(snap: TrackingSnapshot) {
        val ctx = localised()
        ensureChannels(ctx)
        val time = HHMM.format(
            Instant.ofEpochSecond(snap.focused.departureTimestamp + snap.focused.delay * 60L)
                .atZone(ZoneId.systemDefault()),
        )
        val body = ctx.getString(CoreR.string.leg_places_fmt, snap.focused.lineNumber, snap.focused.destination) +
            " · " + time
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(ctx.getString(R.string.approach_alert_title))
            .setContentText(body)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(tapIntent(snap))
            .build()
        getSystemService(NotificationManager::class.java).notify(APPROACH_NOTIF_ID, notification)
    }

    // ---- Notification rendering ----

    // Notifications render outside any activity, so resolve strings through a
    // context wrapped in the stored per-app language tag (pre-33 the picker
    // override only reaches activities).
    private fun localised(): Context {
        val tag = runBlocking { AppPrefs(this@TrackingNotificationService).appLanguage.first() }
        return LocaleUtil.localised(this, tag)
    }

    private fun render(snap: TrackingSnapshot): Notification {
        val ctx = localised()
        ensureChannels(ctx)
        val now = System.currentTimeMillis() / 1000
        val focused = snap.focused
        val effectiveDep = focused.departureTimestamp + focused.delay * 60L

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

        val parts = mutableListOf<String>()
        if (focused.platform.isNotEmpty()) parts += ctx.getString(R.string.platform_full_fmt, focused.platform)
        // Scheduled departure clock time, alongside the live countdown in the
        // chronometer. Same field and zone as the in-app tracking screen.
        parts += HHMM.format(Instant.ofEpochSecond(focused.departureTimestamp).atZone(ZoneId.systemDefault()))
        if (focused.delay > 0) parts += ctx.getString(R.string.delay_plus_fmt, focused.delay)
        if (awaitingProximity) {
            parts += ctx.getString(R.string.tracking_far)
        } else {
            parts += statusText(ctx, status, effectBuf)
        }
        // Sub-minute walks read as "0 min" — at the station, the walk line is noise.
        walkMin?.roundToInt()?.takeIf { it >= 1 }?.let { parts += ctx.getString(R.string.walk_min_fmt, it) }

        val title = ctx.getString(CoreR.string.leg_places_fmt, focused.lineNumber, focused.destination)
        val detail = parts.joinToString(" · ")

        // Draw the in-app diverging bar into a bitmap and mount it in a custom
        // layout. A custom RemoteView can't earn the Android 16 promoted chip,
        // but it renders our exact gapless multi-colour bar in the collapsed
        // shade on every OS version — ProgressStyle only ever draws gapped
        // segments. DecoratedCustomViewStyle keeps the system header, the
        // countdown chronometer and the Stop action; we own only the strip.
        val barBmp = renderBarBitmap(bar)
        // Countdown ticks system-side (elapsedRealtime base), so it keeps
        // running with the app suspended. Once the train is at/past departure,
        // freeze it at 0:00 rather than counting into the negatives; the
        // departed teardown replaces the card within the grace window.
        val departing = effectiveDep * 1000 <= System.currentTimeMillis()
        val countdownBase = android.os.SystemClock.elapsedRealtime() +
            (effectiveDep * 1000 - System.currentTimeMillis())
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
            .setSubText(snap.stationName)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setShowWhen(false)
            .setContentIntent(tapIntent(snap))
            .setGroup(GROUP_KEY)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, stopLabel, stopIntent())
            .build()
    }

    // Render the tracking-bar model as a small ARGB bitmap: contiguous coloured
    // runs across the buffer axis with rounded ends and a faint centre hairline,
    // matching the in-app TrackingBar. fitXY stretches it to the notification
    // width, so the modest fixed size stays well under the ~1 MB RemoteViews
    // transaction budget.
    private fun renderBarBitmap(bar: BarModel): Bitmap {
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
            paint.color = zoneColor(run.zone)
            val next = x + run.length * unit
            canvas.drawRect(x, 0f, next, h.toFloat(), paint)
            x = next
        }
        // Centre marker: the zero-margin hairline, subtle like the in-app bar.
        paint.color = BAR_CENTRE
        val cx = w / 2f
        val half = w * 0.005f
        canvas.drawRect(cx - half, 0f, cx + half, h.toFloat(), paint)
        return bmp
    }

    // Bar colours on the notification's own track: verdict colours pop, the
    // empty axis and centre hairline stay dim so the meaningful run reads on
    // its own against a light or dark shade.
    private fun zoneColor(zone: BarZone): Int = when (zone) {
        BarZone.DARK_GREEN -> 0xFF1E8E3E.toInt()
        BarZone.LIGHT_GREEN -> 0xFF6FCF82.toInt()
        BarZone.AMBER -> 0xFFE08A00.toInt()
        BarZone.DARK_RED -> 0xFFD32F2F.toInt()
        // No-GPS fills the whole bar, so it stays a clearly visible mid grey.
        BarZone.GREY -> 0xFF6B7076.toInt()
        // The empty axis: a dim grey a hair above the charcoal card, so unfilled
        // regions recede instead of reading as bright cut-off sections.
        BarZone.TRACK -> 0xFF2E3238.toInt()
    }

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

    // Render the main gradient-bar card and, on Android 16+, the companion chip.
    private fun pushNotification(snap: TrackingSnapshot) {
        notifySilently(render(snap))
        updateCompanion(snap)
    }

    // The status-bar / OEM-island chip. The gradient-bar card is a custom
    // RemoteView, which can never be promoted (containsCustomViews disqualifies
    // it), so the chip is a second, minimal, standard-template notification:
    // NOT colorized (colorize also disqualifies promotion), a small icon tinted
    // green/amber/red by the ahead/behind verdict, and the countdown as short
    // critical text. Grouped with the card to keep the shade tidy. API 36+ only;
    // older versions have no chip, so there is nothing to duplicate.
    private fun updateCompanion(snap: TrackingSnapshot) {
        if (Build.VERSION.SDK_INT < 36) return
        val ctx = localised()
        ensureChannels(ctx)
        val now = System.currentTimeMillis() / 1000
        val focused = snap.focused
        val walkMin = snap.walkDistMeters?.let { GeoUtils.walkMinutes(it) }
        val gpsOk = snap.gpsOk && walkMin != null
        val effectBuf = TrackingLogic.effectiveBuffer(focused, walkMin ?: 0.0, now)
        val tint = when (TrackingLogic.status(effectBuf, gpsOk)) {
            TrackingStatus.AHEAD -> zoneColor(BarZone.DARK_GREEN)
            TrackingStatus.BEHIND -> zoneColor(BarZone.DARK_RED)
            TrackingStatus.ON_TIME -> zoneColor(BarZone.AMBER)
            else -> zoneColor(BarZone.GREY)
        }
        val effMins = (focused.minutesUntil(now) + focused.delay).roundToInt()
        val short = if (effMins in 0..90) {
            ctx.getString(R.string.n_min_fmt, effMins)
        } else {
            HHMM.format(
                Instant.ofEpochSecond(focused.departureTimestamp + focused.delay * 60L)
                    .atZone(ZoneId.systemDefault()),
            )
        }
        val chip = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(ctx.getString(CoreR.string.leg_places_fmt, focused.lineNumber, focused.destination))
            .setContentText(ctx.getString(R.string.tracking_now))
            .setColor(tint)
            .setColorized(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShortCriticalText(short)
            .setRequestPromotedOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(tapIntent(snap))
            .setGroup(GROUP_KEY)
            .build()
        getSystemService(NotificationManager::class.java).notify(PROMOTED_NOTIF_ID, chip)
    }

    private fun cancelCompanion() {
        getSystemService(NotificationManager::class.java).cancel(PROMOTED_NOTIF_ID)
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
            .setContentIntent(tapIntent(snap))
            .build()
        getSystemService(NotificationManager::class.java).notify(ALERT_NOTIF_ID, notification)
    }

    // Departure passed while backgrounded: swap to a dismissible "Departed
    // HH:MM" that cleans itself up, and end the service. A foregrounded app
    // never reaches this (the VM auto-exits first and stops the service).
    private fun finishDeparted(snap: TrackingSnapshot) {
        val ctx = localised()
        val time = HHMM.format(
            Instant.ofEpochSecond(snap.focused.departureTimestamp + snap.focused.delay * 60L)
                .atZone(ZoneId.systemDefault()),
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(ctx.getString(CoreR.string.leg_places_fmt, snap.focused.lineNumber, snap.focused.destination))
            .setContentText(ctx.getString(R.string.departed_at_fmt, time))
            .setAutoCancel(true)
            .setTimeoutAfter(DEPARTED_TIMEOUT_MS)
            .build()
        cancelCompanion()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification)
        stopSelf()
    }

    private fun stopSession() {
        cancelCompanion()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        locationCallback?.let {
            LocationServices.getFusedLocationProviderClient(this).removeLocationUpdates(it)
        }
        scope.cancel()
        super.onDestroy()
    }

    private fun ensureChannels(ctx: Context) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                ctx.getString(R.string.live_tracking_channel),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
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
        private const val ALERT_CHANNEL_ID = "tracking_alerts"
        private const val NOTIF_ID = 3
        private const val ALERT_NOTIF_ID = 4
        private const val APPROACH_NOTIF_ID = 5
        private const val PROMOTED_NOTIF_ID = 6
        private const val GROUP_KEY = "traintime_tracking"
        // How long to sleep between wakes on the paused (> 6 h) tier: no fetch,
        // no GPS, just a periodic clock check to notice the departure nearing.
        private const val PAUSED_WAKE_SEC = 300L
        private const val FIX_MAX_AGE_MS = 3 * 60 * 1000L
        private const val DEPARTED_TIMEOUT_MS = 60_000L

        const val ACTION_STOP = "com.evanjt.traintime.session.STOP"
        private const val EXTRA_CMD = "cmd"
        private const val EXTRA_STATION_NAME = "stationName"
        private const val EXTRA_STATION_LAT = "stationLat"
        private const val EXTRA_STATION_LON = "stationLon"
        private const val EXTRA_WALK_DIST = "walkDist"
        private const val EXTRA_GPS_OK = "gpsOk"
        private const val EXTRA_STARTED = "started"

        fun start(context: Context, snapshot: TrackingSnapshot) {
            val intent = Intent(context, TrackingNotificationService::class.java)
                .putExtra(EXTRA_CMD, WearSync.json.encodeToString(TrackCommand.from(snapshot.focused, snapshot.stationId)))
                .putExtra(EXTRA_STATION_NAME, snapshot.stationName)
                .putExtra(EXTRA_STARTED, snapshot.startedEpochSeconds)
                .putExtra(EXTRA_GPS_OK, snapshot.gpsOk)
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
