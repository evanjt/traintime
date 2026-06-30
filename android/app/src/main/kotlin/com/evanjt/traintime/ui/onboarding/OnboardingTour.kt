package com.evanjt.traintime.ui.onboarding

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material.icons.outlined.PushPin
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
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
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
fun OnboardingTour(onComplete: () -> Unit) {
    var stepIndex by remember { mutableStateOf(0) }
    var trackingActive by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf(TransportMode.TRAIN) }
    var favourites by remember { mutableStateOf(emptyList<Favourite>()) }
    var pinnedIds by remember { mutableStateOf(emptySet<String>()) }
    var targetRect by remember { mutableStateOf<Rect?>(null) }

    val base = remember { System.currentTimeMillis() / 1000 }
    val departures = remember(base) { TourMockData.departures(base) }
    val step = tourSteps[stepIndex]
    val onReport: (Rect) -> Unit = { targetRect = it }

    fun goNext() {
        targetRect = null
        when {
            step.stage == TourStage.TRACK && !trackingActive -> trackingActive = true
            stepIndex < tourSteps.lastIndex -> {
                if (step.stage == TourStage.TRACK) trackingActive = false
                stepIndex++
            }
            else -> onComplete()
        }
    }

    fun goBack() {
        targetRect = null
        when {
            step.stage == TourStage.TRACK && trackingActive -> trackingActive = false
            stepIndex > 0 -> {
                trackingActive = false
                stepIndex--
            }
        }
    }

    fun toggleFavourite(d: Departure) {
        val match = favourites.firstOrNull { it.lineNumber == d.lineNumber && it.destination == d.destination }
        favourites = if (match != null) {
            favourites - match
        } else {
            favourites + Favourite(TourMockData.STATION_ID, TourMockData.STATION_NAME, d.lineNumber, d.destination)
        }
    }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val windowHeightPx = constraints.maxHeight.toFloat()

            // Live mocked surface for this step.
            Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                when (step.stage) {
                    TourStage.NEARBY -> TourStationSurface(
                        mode, favourites, departures, StationHighlight.LIST, onReport, {}, {},
                    )
                    TourStage.TRACK ->
                        if (trackingActive) {
                            TourTrackingSurface(base, mode, onReport)
                        } else {
                            TourStationSurface(
                                mode, favourites, departures, StationHighlight.TRACK_ROW,
                                onReport, onTrack = { goNext() }, onToggleFav = {},
                            )
                        }
                    TourStage.FAVOURITE -> TourStationSurface(
                        mode, favourites, departures, StationHighlight.FAV_ROW,
                        onReport, onTrack = {}, onToggleFav = ::toggleFavourite,
                    )
                    TourStage.PIN -> TourPickerSurface(
                        pinnedIds, onReport, onPin = { pinnedIds = pinnedIds + it.id },
                    )
                    TourStage.SETTINGS -> TourSettingsSurface(mode, onReport, onSelect = { mode = it })
                    TourStage.WATCH -> TourWatchSurface(onReport)
                    TourStage.WIDGET -> TourWidgetSurface(onReport)
                }
            }

            // Light dim of the surroundings, target stays bright. Drawn in root
            // coordinates so the cut-out aligns with boundsInRoot() of the target.
            SpotlightScrim(targetRect, Modifier.fillMaxSize())

            // Anchored callout, placed in the screen half opposite the target.
            val targetCenterY = targetRect?.center?.y
            val bubbleAtBottom = targetCenterY == null || targetCenterY < windowHeightPx / 2f
            val bodyText = if (step.stage == TourStage.TRACK && trackingActive) TRACK_DETAIL_BODY else step.body
            val nextLabel = if (stepIndex == tourSteps.lastIndex) "Done" else "Next"

            Box(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
                CalloutBubble(
                    title = step.title,
                    body = bodyText,
                    index = stepIndex,
                    total = tourSteps.size,
                    caretUp = bubbleAtBottom,
                    onBack = ::goBack,
                    onSkip = onComplete,
                    onNext = ::goNext,
                    nextLabel = nextLabel,
                    modifier = Modifier.align(if (bubbleAtBottom) Alignment.BottomCenter else Alignment.TopCenter),
                )
            }
        }
    }
}

private enum class StationHighlight { LIST, TRACK_ROW, FAV_ROW }

@Composable
private fun TourStationSurface(
    mode: TransportMode,
    favourites: List<Favourite>,
    departures: List<Departure>,
    highlight: StationHighlight,
    onReport: (Rect) -> Unit,
    onTrack: () -> Unit,
    onToggleFav: (Departure) -> Unit,
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
            ModePicker(availableModes = listOf(TransportMode.TRAIN), currentMode = mode, onSelect = {})
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
                    val isTarget = when (highlight) {
                        StationHighlight.TRACK_ROW -> d.lineNumber == TourMockData.TRACK_LINE
                        StationHighlight.FAV_ROW -> d.lineNumber == TourMockData.FAVOURITE_LINE
                        StationHighlight.LIST -> false
                    }
                    val rowModifier = Modifier
                        .fillMaxWidth()
                        .then(if (isTarget) Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) } else Modifier)
                        .then(
                            if (isTarget) {
                                Modifier.clickable {
                                    when (highlight) {
                                        StationHighlight.TRACK_ROW -> onTrack()
                                        StationHighlight.FAV_ROW -> onToggleFav(d)
                                        StationHighlight.LIST -> {}
                                    }
                                }
                            } else {
                                Modifier
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
    val focused = remember(base) { TourMockData.focused(base) }
    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) {
        while (true) {
            nowSeconds = System.currentTimeMillis() / 1000
            delay(250)
        }
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

        // Countdown + tracking bar — the heart of tracking, so spotlight this block.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .onGloballyPositioned { onReport(it.boundsInRoot()) },
        ) {
            Text(
                focused.countdownText(nowSeconds),
                color = palette.minutesSoon,
                fontSize = 56.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(vertical = 8.dp),
            )
            TrackingBar(
                schedBuf = 1.5,
                effectBuf = 2.5,
                hasGps = true,
                modifier = Modifier.padding(horizontal = 24.dp),
            )
            Text(
                "3 min ahead",
                color = palette.ahead,
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
            Text(GeoUtils.formatWalkInfo(260.0), color = secondary, fontSize = 14.sp)
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

// Mocked watch-sync surface: a station header with the green (live) watch icon —
// the spotlight target — over a Watch-link card mirroring SettingsSheet's section.
// Self-contained: no real watch, the colours/labels match the bridge's watch UI.
// internal (not private) so the onboarding snapshot test can render it.
@Composable
internal fun TourWatchSurface(onReport: (Rect) -> Unit) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val onSurface = MaterialTheme.colorScheme.onSurface
    val live = Color(0xFF34C759)
    var mirror by remember { mutableStateOf(true) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 16.dp, vertical = 24.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        ) {
            Text(
                TourMockData.STATION_NAME,
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.Filled.Watch,
                contentDescription = "Watch linked",
                tint = live,
                modifier = Modifier.size(30.dp).onGloballyPositioned { onReport(it.boundsInRoot()) },
            )
        }

        val context = LocalContext.current
        Column(
            Modifier
                .fillMaxWidth()
                .padding(top = 24.dp)
                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(16.dp))
                .padding(16.dp),
        ) {
            Text("Watch link", color = secondary, fontSize = 13.sp)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            ) {
                Icon(Icons.Filled.Watch, contentDescription = null, tint = secondary, modifier = Modifier.size(20.dp))
                Text("Garmin", color = onSurface, modifier = Modifier.padding(start = 12.dp))
                Spacer(Modifier.weight(1f))
                Text("Connected", color = live, fontSize = 13.sp)
            }
            Text(
                "Works on fēnix, Forerunner, venu, epix, vívoactive and more.",
                color = secondary,
                fontSize = 12.sp,
            )
            Text(
                "View on Connect IQ store",
                color = palette.platform,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .padding(top = 8.dp)
                    .clickable {
                        runCatching {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(CONNECT_IQ_STORE_URL)))
                        }
                    },
            )
            Text(
                "Wear OS support is coming soon.",
                color = secondary.copy(alpha = 0.6f),
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Mirror to watch", color = onSurface)
                    Text(
                        "Send your tracked train, mode, station and location to the watch",
                        color = secondary,
                        fontSize = 12.sp,
                    )
                }
                Switch(checked = mirror, onCheckedChange = { mirror = it })
            }
        }
    }
}

private const val CONNECT_IQ_STORE_URL =
    "https://apps.garmin.com/apps/c70bbfae-846a-4d00-9e96-d485217035fb"

@Composable
private fun TourWidgetSurface(onReport: (Rect) -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp),
    ) {
        Box(Modifier.onGloballyPositioned { onReport(it.boundsInRoot()) }) {
            TourWidgetMock()
        }
        Spacer(Modifier.height(24.dp))
        AddWidgetButton()
    }
}
