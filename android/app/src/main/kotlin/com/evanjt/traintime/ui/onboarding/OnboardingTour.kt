package com.evanjt.traintime.ui.onboarding

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.Favourite
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.data.prefs.FavouritesStore
import com.evanjt.traintime.data.prefs.MyStationsStore
import com.evanjt.traintime.domain.GeoUtils
import com.evanjt.traintime.linePill
import com.evanjt.traintime.ui.station.DepartureRow
import com.evanjt.traintime.ui.station.ModePicker
import com.evanjt.traintime.ui.station.icon
import com.evanjt.traintime.ui.tracking.DirectionArrow
import com.evanjt.traintime.ui.tracking.FormationDiagram
import com.evanjt.traintime.ui.tracking.TrackingBar
import kotlinx.coroutines.delay

// Guided coach-mark walkthrough. Each step renders a real, mocked app surface
// and spotlights one feature with an anchored callout. All state is local
// (mode/favourites/pins live only here), so toggling things in the tour never
// touches the user's real data. onComplete fires on Finish AND Skip.
@Composable
fun OnboardingTour(steps: List<TourStep> = tourSteps, onComplete: () -> Unit) {
    var stepIndex by remember { mutableStateOf(0) }
    // Slide direction for the page transition: 1 forward, -1 back.
    var navDirection by remember { mutableStateOf(1) }
    var trackingActive by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf(TransportMode.TRAIN) }
    var favourites by remember { mutableStateOf(emptyList<Favourite>()) }
    var pinnedIds by remember { mutableStateOf(emptySet<String>()) }
    var targetRect by remember { mutableStateOf<Rect?>(null) }

    val base = remember { System.currentTimeMillis() / 1000 }
    val departures = remember(base, mode) { TourMockData.departures(base, mode) }
    val step = steps[stepIndex]
    val palette = LocalAppPalette.current
    val onReport: (Rect) -> Unit = { targetRect = it }

    fun toggleFavourite(d: Departure) {
        // Clear the spotlight so it re-anchors (or clears) for the new favourite state.
        targetRect = null
        val match = favourites.firstOrNull { it.lineNumber == d.lineNumber && it.destination == d.destination }
        favourites = if (match != null) {
            favourites - match
        } else {
            favourites + Favourite(TourMockData.STATION_ID, TourMockData.STATION_NAME, d.lineNumber, d.destination)
        }
    }

    fun goNext() {
        navDirection = 1
        targetRect = null
        when {
            step.stage == TourStage.TRACK && !trackingActive -> trackingActive = true
            // First Next on the favourite step stars the line (so the user sees it land above
            // and below) before advancing.
            step.stage == TourStage.FAVOURITE && favourites.isEmpty() ->
                departures.firstOrNull { it.lineNumber == TourMockData.FAVOURITE_LINE }?.let { toggleFavourite(it) }
            stepIndex < steps.lastIndex -> {
                if (step.stage == TourStage.TRACK) trackingActive = false
                // Leaving the mode step returns the board to trains so the
                // TRACK/FAVOURITE steps find IC1 and IR15.
                if (step.stage == TourStage.MODE) mode = TransportMode.TRAIN
                stepIndex++
            }
            else -> onComplete()
        }
    }

    fun goBack() {
        navDirection = -1
        targetRect = null
        when {
            step.stage == TourStage.TRACK && trackingActive -> trackingActive = false
            step.stage == TourStage.FAVOURITE && favourites.isNotEmpty() -> favourites = emptyList()
            stepIndex > 0 -> {
                trackingActive = false
                if (step.stage == TourStage.MODE) mode = TransportMode.TRAIN
                stepIndex--
            }
        }
    }

    Surface(
        Modifier
            .fillMaxSize()
            // Swipe left/right to move between tour pages.
            .pointerInput(stepIndex, trackingActive) {
                var dragX = 0f
                detectHorizontalDragGestures(
                    onDragStart = { dragX = 0f },
                    onDragEnd = { if (dragX <= -80f) goNext() else if (dragX >= 80f) goBack() },
                    onHorizontalDrag = { _, delta -> dragX += delta },
                )
            },
        color = MaterialTheme.colorScheme.background,
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val windowHeightPx = constraints.maxHeight.toFloat()
            val density = LocalDensity.current
            // Informational pages (no spotlight target inside the app UI) put the
            // callout at the top and scroll the illustration below it, so a tall
            // card (the watch shots) is never hidden, on any screen density.
            val infoStage = step.stage == TourStage.SHARE || step.stage == TourStage.ROUTE_PLAN ||
                step.stage == TourStage.WATCH || step.stage == TourStage.WIDGET
            var bubbleHeightDp by remember { mutableStateOf(0.dp) }
            val infoInset = bubbleHeightDp + 24.dp

            // Live mocked surface for this step, sliding horizontally as pages change.
            AnimatedContent(
                targetState = stepIndex,
                transitionSpec = {
                    (slideInHorizontally(tween(300)) { w -> navDirection * w } + fadeIn(tween(300))) togetherWith
                        (slideOutHorizontally(tween(300)) { w -> -navDirection * w } + fadeOut(tween(300)))
                },
                label = "tourSurface",
            ) { idx ->
                val s = steps[idx]
                // Only the settled page drives the spotlight, so the outgoing page
                // sliding away doesn't jitter the highlight.
                val report: (Rect) -> Unit = if (idx == stepIndex) onReport else { _ -> }
                Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                    when (s.stage) {
                        TourStage.NEARBY -> TourStationSurface(
                            mode, favourites, departures, StationHighlight.LIST, report, {}, {},
                        )
                        TourStage.MODE -> TourStationSurface(
                            mode, favourites, departures, StationHighlight.MODE_CHIPS,
                            report, onTrack = {}, onToggleFav = {}, onSelectMode = { mode = it },
                        )
                        TourStage.TRACK ->
                            if (trackingActive) {
                                TourTrackingSurface(base, mode, report)
                            } else {
                                TourStationSurface(
                                    mode, favourites, departures, StationHighlight.TRACK_ROW,
                                    report, onTrack = { goNext() }, onToggleFav = {},
                                )
                            }
                        TourStage.FAVOURITE -> TourStationSurface(
                            mode, favourites, departures, StationHighlight.FAV_ROW,
                            report, onTrack = {}, onToggleFav = ::toggleFavourite,
                        )
                        TourStage.PIN -> TourPickerSurface(
                            pinnedIds, report, onPin = { pinnedIds = pinnedIds + it.id },
                        )
                        TourStage.SETTINGS -> TourSettingsSurface(mode, report, onSelect = { mode = it })
                        TourStage.SHARE -> TourShareSurface(infoInset, report)
                        TourStage.ROUTE_PLAN -> TourRouteSurface(infoInset, report)
                        TourStage.WATCH -> TourWatchSurface(infoInset, report)
                        TourStage.WIDGET -> TourWidgetSurface(infoInset, report)
                    }
                }
            }

            // Light dim of the surroundings, target stays bright. Drawn in root
            // coordinates so the cut-out aligns with boundsInRoot() of the target.
            SpotlightScrim(targetRect, palette.platform, modifier = Modifier.fillMaxSize())

            // Anchored callout. Place it below unless the target itself sits low on screen,
            // so a tall target (eg. the full departures list) keeps the bubble at the bottom
            // instead of overlapping the interface up top.
            val targetTop = targetRect?.top
            val bubbleAtBottom = if (infoStage) false else (targetTop == null || targetTop < windowHeightPx * 0.55f)
            val bodyText = when {
                step.stage == TourStage.TRACK && trackingActive -> TRACK_DETAIL_BODY
                step.stage == TourStage.FAVOURITE && favourites.isNotEmpty() -> FAVOURITE_DETAIL_BODY
                else -> step.body
            }
            val nextLabel = if (stepIndex == steps.lastIndex) "Done" else "Next"

            val (dotIndex, dotTotal) = tourDotPosition(steps, stepIndex, trackingActive, favourites.isNotEmpty())

            // Anchored title/body bubble. When it sits at the bottom it clears the
            // fixed nav bar below it.
            Box(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
                CalloutBubble(
                    title = step.title,
                    body = bodyText,
                    caretUp = bubbleAtBottom,
                    modifier = Modifier
                        .align(if (bubbleAtBottom) Alignment.BottomCenter else Alignment.TopCenter)
                        .padding(bottom = if (bubbleAtBottom) 76.dp else 0.dp)
                        .onGloballyPositioned { bubbleHeightDp = with(density) { it.size.height.toDp() } },
                )
            }

            // Fixed navigation bar, pinned to the bottom so Back / Next never move.
            Box(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
                TourNavBar(
                    index = dotIndex,
                    total = dotTotal,
                    onBack = ::goBack,
                    onSkip = onComplete,
                    onNext = ::goNext,
                    nextLabel = nextLabel,
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
            }
        }
    }
}

private enum class StationHighlight { LIST, MODE_CHIPS, TRACK_ROW, FAV_ROW }

@Composable
private fun TourStationSurface(
    mode: TransportMode,
    favourites: List<Favourite>,
    departures: List<Departure>,
    highlight: StationHighlight,
    onReport: (Rect) -> Unit,
    onTrack: () -> Unit,
    onToggleFav: (Departure) -> Unit,
    onSelectMode: (TransportMode) -> Unit = {},
) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val favDeps = FavouritesStore.extract(favourites, departures)
    val isFav: (Departure) -> Boolean = { d ->
        favourites.any { it.lineNumber == d.lineNumber && it.destination == d.destination }
    }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp),
        ) {
            ModePicker(
                availableModes = listOf(TransportMode.TRAIN, TransportMode.BUS, TransportMode.TRAM),
                currentMode = mode,
                onSelect = onSelectMode,
                modifier = if (highlight == StationHighlight.MODE_CHIPS) {
                    Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) }
                } else {
                    Modifier
                },
            )
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.LocationOn, contentDescription = "GPS", tint = palette.ahead)
            IconButton(onClick = {}) {
                Icon(Icons.Filled.Settings, contentDescription = "Settings", tint = secondary)
            }
        }

        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
        ) {
            Text(
                TourMockData.STATION_NAME,
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = secondary)
        }
        Text(
            GeoUtils.formatWalkInfo(260.0),
            color = secondary,
            fontSize = 13.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 8.dp),
        )

        val cardModifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp)
            .padding(bottom = 12.dp)
            .then(
                if (highlight == StationHighlight.LIST) {
                    Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) }
                } else {
                    Modifier
                },
            )
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
            modifier = cardModifier,
        ) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                favDeps.forEach { d ->
                    DepartureRow(departure = d, isFavourite = true, mode = mode)
                }
                if (favDeps.isNotEmpty()) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp)
                            .height(2.dp)
                            .background(palette.favouriteSeparator),
                    )
                }
                departures.forEachIndexed { index, d ->
                    val isTrackTarget = highlight == StationHighlight.TRACK_ROW && d.lineNumber == TourMockData.TRACK_LINE
                    // The favourite target only spotlights until it's starred; afterwards the
                    // line shows above and below with no dim, so both occurrences are visible.
                    val isFavTarget = highlight == StationHighlight.FAV_ROW &&
                        d.lineNumber == TourMockData.FAVOURITE_LINE && favourites.isEmpty()
                    val isTarget = isTrackTarget || isFavTarget
                    val rowModifier = Modifier
                        .fillMaxWidth()
                        .then(if (isTarget) Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) } else Modifier)
                        .then(
                            when {
                                isTrackTarget -> Modifier.clickable { onTrack() }
                                // Favourite via long-press, the real station-screen gesture.
                                isFavTarget -> Modifier.combinedClickable(onClick = {}, onLongClick = { onToggleFav(d) })
                                else -> Modifier
                            },
                        )
                    Box(rowModifier) {
                        DepartureRow(departure = d, isFavourite = isFav(d), mode = mode)
                    }
                    if (index < departures.lastIndex) {
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.12f),
                            modifier = Modifier.padding(horizontal = 16.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TourTrackingSurface(base: Long, mode: TransportMode, onReport: (Rect) -> Unit) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val walkMin = GeoUtils.walkMinutes(TOUR_TRACK_DISTANCE_M)

    // A live, looping simulation: the departure is a fixed runway ahead and counts down in real
    // time. The buffer (time left minus walk time) drives the bar and status exactly like the
    // real app, so the user sees it shift from comfortable to tight. Looping keeps it live and
    // never freezes on "Departed".
    var start by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) {
        while (true) {
            nowSeconds = System.currentTimeMillis() / 1000
            if (nowSeconds - start >= TOUR_TRACK_RUNWAY_SEC) start = nowSeconds
            delay(250)
        }
    }
    val depTs = start + TOUR_TRACK_RUNWAY_SEC
    val focused = remember(base) { TourMockData.focused(base) }.copy(departureTimestamp = depTs)
    val minutesLeft = (depTs - nowSeconds) / 60.0
    val effectBuf = minutesLeft - walkMin
    // Same status wording as the real tracking screen (MainViewModel.trackingStatusText).
    val absBuf = kotlin.math.abs(effectBuf)
    val statusText = when {
        absBuf < 0.5 -> "On time"
        else -> {
            val unit = if (absBuf < 1.5) "${(absBuf * 60).toInt()}s" else "${absBuf.toInt()} min"
            if (effectBuf > 0) "$unit ahead" else "$unit behind"
        }
    }
    val statusColor = when {
        effectBuf > 0.5 -> palette.ahead
        effectBuf < -0.5 -> palette.behind
        else -> palette.onTime
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 24.dp),
    ) {
        Text(TourMockData.STATION_NAME, color = secondary, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp))

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(top = 12.dp),
        ) {
            Text(
                focused.lineNumber,
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .background(palette.linePill(focused.lineNumber, mode), RoundedCornerShape(7.dp))
                    .padding(horizontal = 8.dp, vertical = 3.dp),
            )
            Text(
                focused.destination,
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
            )
        }

        Text(
            "Platform ${focused.platform}",
            color = secondary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(top = 4.dp),
        )

        // Countdown + tracking bar, the heart of tracking, so spotlight this block.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .onGloballyPositioned { onReport(it.boundsInRoot()) },
        ) {
            Text(
                focused.countdownText(nowSeconds),
                color = if (minutesLeft < 2.0) palette.minutesNow else palette.minutesSoon,
                fontSize = 56.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(vertical = 8.dp),
            )
            TrackingBar(
                schedBuf = effectBuf,
                effectBuf = effectBuf,
                hasGps = true,
                modifier = Modifier.padding(horizontal = 24.dp),
            )
            Text(
                statusText,
                color = statusColor,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 12.dp),
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(top = 8.dp),
        ) {
            DirectionArrow(45.0)
            Text(GeoUtils.formatWalkInfo(TOUR_TRACK_DISTANCE_M), color = secondary, fontSize = 14.sp)
        }

        FormationDiagram(TourMockData.formation, Modifier.padding(top = 16.dp))
    }
}

@Composable
private fun TourPickerSurface(
    pinnedIds: Set<String>,
    onReport: (Rect) -> Unit,
    onPin: (Station) -> Unit,
) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val stations = MyStationsStore.reorder(TourMockData.nearbyStations, pinnedIds)

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(16.dp)) {
        Text(
            "Nearby stations",
            color = MaterialTheme.colorScheme.onBackground,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        stations.forEachIndexed { index, station ->
            val pinned = station.id in pinnedIds
            val isBern = station.id == TourMockData.STATION_ID
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(station.name ?: "", color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Medium)
                    Text(station.walkInfo(index, stations.size), color = secondary, fontSize = 12.sp)
                }
                val pinModifier = if (isBern) Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) } else Modifier
                IconButton(onClick = { if (isBern) onPin(station) }, modifier = pinModifier) {
                    Icon(
                        if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                        contentDescription = "Pin",
                        tint = if (pinned) palette.platform else secondary,
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.12f))
        }
    }
}

@Composable
private fun TourSettingsSurface(
    currentMode: TransportMode,
    onReport: (Rect) -> Unit,
    onSelect: (TransportMode) -> Unit,
) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val onSurface = MaterialTheme.colorScheme.onSurface

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(horizontal = 20.dp, vertical = 24.dp)) {
        Text(
            "Settings",
            color = onSurface,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 16.dp),
        )
        Column(Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) }) {
            Text("Default Mode", color = secondary, fontSize = 13.sp)
            listOf(TransportMode.TRAIN, TransportMode.BUS, TransportMode.TRAM).forEach { m ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { onSelect(m) }.padding(vertical = 10.dp),
                ) {
                    Icon(m.icon, contentDescription = null, tint = secondary, modifier = Modifier.size(20.dp))
                    Text(m.label, color = onSurface, modifier = Modifier.padding(start = 12.dp))
                    Spacer(Modifier.weight(1f))
                    if (currentMode == m) {
                        Icon(Icons.Filled.Check, contentDescription = "Selected", tint = palette.platform)
                    }
                }
            }
        }
    }
}

// Mocked watch showcase: a real screenshot of each watch app with a capability badge and its own
// store button beneath the face. The card is the spotlight target. On Android the Apple Watch app
// installs but pairs with an iPhone, so its badge reads "Works with iPhone", an advert, not a
// pairing. internal (not private) so the onboarding snapshot test can render it.
@Composable
internal fun TourWatchSurface(topInset: Dp, onReport: (Rect) -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant

    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(top = topInset, bottom = 96.dp)
            .padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .onGloballyPositioned { onReport(it.boundsInRoot()) }
                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(16.dp))
                .padding(16.dp),
        ) {
            // 2 + 1: the Android-relevant pair first, the iPhone advert beneath.
            // Three abreast truncates on 360 dp phones.
            Row(
                horizontalArrangement = Arrangement.spacedBy(18.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                WatchTile(
                    R.drawable.watch_garmin,
                    name = "Garmin",
                    badge = WatchBadgeKind.SYNCS_LIVE,
                    modifier = Modifier.weight(1f),
                    buttonLabel = "Connect IQ",
                    url = CONNECT_IQ_STORE_URL,
                )
                WatchTile(
                    R.drawable.watch_wear,
                    name = "Wear OS",
                    badge = WatchBadgeKind.COMING_SOON,
                    modifier = Modifier.weight(1f),
                )
            }
            Row(
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
            ) {
                WatchTile(
                    R.drawable.watch_apple,
                    name = "Apple Watch",
                    badge = WatchBadgeKind.PHONE_APP,
                    modifier = Modifier.fillMaxWidth(0.5f),
                    buttonLabel = "App Store",
                    url = APP_STORE_URL,
                )
            }
            Text(
                "Track on your phone and a departure mirrors to a paired watch, which also reads " +
                    "the phone's location, handy indoors. The watch icon turns green when it's live.",
                color = secondary,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
}

// One watch app: the framed device shot (bezel + bands, reused from the web docs), its name, a
// capability badge and an optional store button. Shown whole (Fit) so the device reads as a watch.
@Composable
private fun WatchTile(
    resId: Int,
    name: String,
    badge: WatchBadgeKind,
    modifier: Modifier = Modifier,
    buttonLabel: String? = null,
    url: String? = null,
) {
    val context = LocalContext.current
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            painter = painterResource(resId),
            contentDescription = name,
            contentScale = ContentScale.Fit,
            modifier = Modifier.height(120.dp),
        )
        Spacer(Modifier.height(8.dp))
        Text(
            name,
            fontWeight = FontWeight.SemiBold,
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.height(6.dp))
        WatchBadge(badge)
        if (buttonLabel != null && url != null) {
            FilledTonalButton(
                onClick = {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                },
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                modifier = Modifier.padding(top = 8.dp).height(30.dp),
            ) {
                Icon(Icons.Filled.OpenInNew, contentDescription = null, modifier = Modifier.size(13.dp))
                Spacer(Modifier.width(4.dp))
                Text(buttonLabel, fontSize = 12.sp)
            }
        }
    }
}

internal enum class WatchBadgeKind { SYNCS_LIVE, COMING_SOON, PHONE_APP }

// Graphical capability chip: green tick when the watch syncs with this phone, a clock while Wear
// support is unreleased, a neutral phone glyph for the iPhone-paired Apple Watch advert.
@Composable
private fun WatchBadge(kind: WatchBadgeKind) {
    val green = Color(0xFF34C759)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val icon = when (kind) {
        WatchBadgeKind.SYNCS_LIVE -> Icons.Filled.Check
        WatchBadgeKind.COMING_SOON -> Icons.Filled.Schedule
        WatchBadgeKind.PHONE_APP -> Icons.Filled.PhoneIphone
    }
    val label = when (kind) {
        WatchBadgeKind.SYNCS_LIVE -> "Syncs live"
        WatchBadgeKind.COMING_SOON -> "Coming soon"
        WatchBadgeKind.PHONE_APP -> "For iPhone"
    }
    val tint = if (kind == WatchBadgeKind.SYNCS_LIVE) green else secondary
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(tint.copy(alpha = 0.15f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(14.dp),
        )
        Spacer(Modifier.width(4.dp))
        Text(
            label,
            color = tint,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

private const val CONNECT_IQ_STORE_URL =
    "https://apps.garmin.com/en-CH/apps/c70bbfae-846a-4d00-9e96-d485217035fb"

private const val APP_STORE_URL = "https://apps.apple.com/app/id6760388620"

// Tracking demo: a short, looping countdown so the bar and status visibly shift.
private const val TOUR_TRACK_RUNWAY_SEC = 165L
private const val TOUR_TRACK_DISTANCE_M = 130.0

@Composable
private fun TourWidgetSurface(topInset: Dp, onReport: (Rect) -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(top = topInset, bottom = 96.dp)
            .padding(horizontal = 24.dp),
    ) {
        Box(Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) }) {
            TourWidgetMock()
        }
        Spacer(Modifier.height(24.dp))
        AddWidgetButton()
    }
}

@Composable
private fun TourShareSurface(topInset: Dp, onReport: (Rect) -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(top = topInset, bottom = 96.dp)
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("From the SBB Mobile app", color = secondary, fontSize = 13.sp)
        Spacer(Modifier.height(10.dp))
        Row(
            Modifier
                .fillMaxWidth()
                .onGloballyPositioned { onReport(it.boundsInRoot()) }
                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(16.dp))
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Share to", color = secondary, fontSize = 14.sp)
            Text("TrainTime", style = MaterialTheme.typography.titleMedium)
        }
        Spacer(Modifier.height(16.dp))
        Text("Your trip opens here, tracked and ready.", color = secondary, fontSize = 13.sp)
    }
}

// Mirrors the real route sheet (RouteDetailSheet) so the tour matches the app:
// coloured line pills, a Remind switch, Track now, the current leg highlighted.
@Composable
private fun TourRouteSurface(topInset: Dp, onReport: (Rect) -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(top = topInset, bottom = 96.dp)
            .padding(horizontal = 20.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .onGloballyPositioned { onReport(it.boundsInRoot()) }
                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(16.dp))
                .padding(12.dp),
        ) {
            Text("Route to Lausanne", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
            TourRouteLeg("IR90", "Sion to Lausanne", "13:02 to 13:44", tracked = true, isCurrent = true)
            TourRouteLeg("M2", "Lausanne to Ouchy", "13:52 to 14:01", tracked = false, isCurrent = false)
        }
        Spacer(Modifier.height(12.dp))
        Text("Each connection can send a reminder. Track any now.", color = secondary, fontSize = 13.sp)
    }
}

@Composable
private fun TourRouteLeg(line: String, path: String, times: String, tracked: Boolean, isCurrent: Boolean) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val bg = if (isCurrent) MaterialTheme.colorScheme.surfaceVariant else Color.Transparent
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(bg).padding(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                line,
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(palette.linePill(line, TransportMode.TRAIN))
                    .padding(horizontal = 7.dp, vertical = 2.dp),
            )
            Column(Modifier.weight(1f).padding(start = 8.dp)) {
                Text(path, fontWeight = FontWeight.Medium, maxLines = 1)
                Text(times, color = secondary, fontSize = 12.sp)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Remind", color = secondary, fontSize = 10.sp)
                Switch(checked = tracked, onCheckedChange = {})
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (isCurrent) "Next connection" else "", color = secondary, fontSize = 11.sp)
            Text("Track now", color = palette.platform, fontSize = 14.sp)
        }
    }
}
