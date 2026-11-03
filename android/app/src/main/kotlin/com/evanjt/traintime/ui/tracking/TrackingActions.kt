package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.annotation.StringRes
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.session.MuteLook
import com.evanjt.traintime.session.MuteState

enum class WatchLiveness { OPEN, CLOSED, OFF }

// What the Watch button shows. null hides it (no watch paired).
data class WatchAction(
    val trackingHere: Boolean,
    val checking: Boolean,
    val liveness: WatchLiveness,
)

// The tracking screen's one row of actions: Map, Watch, Sound and Buzz. Tap
// acts, hold does the longer form: the per-watch menu, or the setting for
// every trip.
@Composable
fun TrackingActionRow(
    showMap: Boolean,
    watch: WatchAction?,
    sound: MuteState,
    buzz: MuteState,
    onMap: () -> Unit,
    onWatch: () -> Unit,
    onWatchHold: () -> Unit,
    onSound: () -> Unit,
    onSoundHold: () -> Unit,
    onBuzz: () -> Unit,
    onBuzzHold: () -> Unit,
    modifier: Modifier = Modifier,
    // Applied to Sound and Buzz with their hint, so a caller can find them on screen.
    muteModifier: Modifier = Modifier,
    watchMenu: @Composable () -> Unit = {},
) {
    val palette = LocalAppPalette.current
    // Equal slots, so Sound and Buzz take two together and their hint the width of both.
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
    ) {
        if (showMap) {
            val label = stringResource(R.string.action_map)
            Slot {
                ActionButton(
                    caption = label,
                    description = stringResource(R.string.show_on_map),
                    colour = palette.darkGreen,
                    onClick = onMap,
                ) { tint -> Icon(Icons.Filled.Map, contentDescription = null, tint = tint) }
            }
        }
        if (watch != null) {
            val caption = stringResource(if (watch.trackingHere) R.string.action_watch_on else R.string.action_watch_send)
            val description = stringResource(if (watch.trackingHere) R.string.tracking_on_watch else R.string.track_on_watch)
            Slot {
                Box {
                    ActionButton(
                        caption = caption,
                        description = description,
                        colour = palette.lineRegional,
                        onClick = onWatch,
                        onLongClick = onWatchHold,
                    ) { tint ->
                        if (watch.checking) {
                            CircularProgressIndicator(strokeWidth = 2.dp, color = tint, modifier = Modifier.size(20.dp))
                        } else {
                            Box {
                                Icon(Icons.Filled.Watch, contentDescription = null, tint = tint)
                                Box(
                                    Modifier
                                        .align(Alignment.TopEnd)
                                        .offset(x = 3.dp, y = (-3).dp)
                                        .size(9.dp)
                                        .border(1.5.dp, MaterialTheme.colorScheme.surface, CircleShape)
                                        .padding(1.dp)
                                        .background(livenessColour(watch.liveness), CircleShape),
                                )
                            }
                        }
                    }
                    watchMenu()
                }
            }
        }
        HoldBracket(Modifier.weight(2f).then(muteModifier)) {
            Slot { MuteButton(Icons.Filled.Notifications, stringResource(R.string.alert_sounds), palette.amber, sound, onSound, onSoundHold) }
            Slot { MuteButton(Icons.Filled.Vibration, stringResource(R.string.vibration), palette.lineTram, buzz, onBuzz, onBuzzHold) }
        }
    }
}

@Composable
private fun RowScope.Slot(content: @Composable () -> Unit) {
    Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) { content() }
}

const val HOLD_HINT_TAG = "holdHint"

// Sound and Buzz under one bracket with one line saying what a hold does, so the
// gesture is found without trying it. The bracket and hint are hidden from
// accessibility: the buttons' hold labels already say it. A large font wraps
// the hint to a second line rather than clip it.
@Composable
private fun HoldBracket(modifier: Modifier, buttons: @Composable RowScope.() -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurfaceVariant
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
        Row(Modifier.fillMaxWidth()) { buttons() }
        Canvas(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .height(6.dp),
        ) {
            val stroke = 1.dp.toPx()
            val left = stroke / 2
            val right = size.width - stroke / 2
            val bottom = size.height - stroke / 2
            val line = ink.copy(alpha = 0.5f)
            drawLine(line, Offset(left, 0f), Offset(left, bottom), stroke)
            drawLine(line, Offset(left, bottom), Offset(right, bottom), stroke)
            drawLine(line, Offset(right, bottom), Offset(right, 0f), stroke)
        }
        Text(
            stringResource(R.string.trip_hold_hint),
            color = ink.copy(alpha = 0.75f),
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            lineHeight = 13.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 3.dp)
                .testTag(HOLD_HINT_TAG)
                .clearAndSetSemantics {},
        )
    }
}

private fun livenessColour(liveness: WatchLiveness): Color = when (liveness) {
    WatchLiveness.OPEN -> Color(0xFF34C759)
    WatchLiveness.CLOSED -> Color(0xFFFFB300)
    WatchLiveness.OFF -> Color(0xFF8E8E93)
}

// What a tap did, shown once. Landing back on the setting needs no hint.
@StringRes
fun tripHint(override: Boolean?): Int? = when (override) {
    false -> R.string.trip_muted_hint
    true -> R.string.trip_on_hint
    null -> null
}

// The Settings value, so what a hold flips reads without trying it.
@StringRes
fun usualCaption(state: MuteState): Int =
    if (state.usuallyOn) R.string.trip_usually_on else R.string.trip_usually_off

@Composable
private fun MuteButton(
    icon: ImageVector,
    name: String,
    colour: Color,
    state: MuteState,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val look = state.look
    val usual = stringResource(usualCaption(state))
    val caption = stringResource(
        when (look) {
            MuteLook.ON -> R.string.trip_mute_on
            MuteLook.MUTED_THIS_TRIP -> R.string.trip_mute_this_trip
            MuteLook.OFF -> R.string.trip_mute_off
        },
    )
    ActionButton(
        caption = caption,
        description = "$name, $caption, $usual",
        colour = colour,
        detail = usual,
        onClick = onClick,
        onLongClick = onLongClick,
        onLongClickLabel = stringResource(R.string.trip_mute_hold_label),
        look = look,
    ) { tint ->
        val strikes = when (look) {
            MuteLook.ON -> 0
            MuteLook.MUTED_THIS_TRIP -> 1
            MuteLook.OFF -> 2
        }
        // The halo matches what sits behind the icon: the solid disc when off,
        // the screen through the ring when muted for this trip.
        val halo = if (look == MuteLook.OFF) colour else MaterialTheme.colorScheme.surface
        Icon(
            icon,
            contentDescription = null,
            tint = tint,
            modifier = if (strikes > 0) Modifier.strike(tint, halo, strikes) else Modifier,
        )
    }
}

// Diagonal strikes through the icon, the mark the system uses for a muted bell,
// drawn so the vibration icon can carry it too. One strike is this trip, two
// are every trip. A halo cuts the icon either side of each strike so a pair
// reads as two lines, not one thick one.
private fun Modifier.strike(colour: Color, halo: Color, count: Int): Modifier = drawWithContent {
    drawContent()
    val gap = 3.dp.toPx()
    val stroke = 2.dp.toPx()
    // Offset each line along the perpendicular so a pair sits either side of the diagonal.
    val lines = List(count) { i ->
        val shift = (i - (count - 1) / 2f) * gap
        Offset(size.width * 0.12f + shift, size.height * 0.12f - shift) to
            Offset(size.width * 0.88f + shift, size.height * 0.88f - shift)
    }
    lines.forEach { (a, b) -> drawLine(halo, a, b, strokeWidth = stroke * 2.2f, cap = StrokeCap.Round) }
    lines.forEach { (a, b) -> drawLine(colour, a, b, strokeWidth = stroke, cap = StrokeCap.Round) }
}

// Each button carries its own colour. Three looks: on is a tonal disc, muted
// for this trip an outlined ring, off in Settings a solid disc, so the two
// muted states read apart at a glance.
@Composable
private fun ActionButton(
    caption: String,
    description: String,
    colour: Color,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    onLongClickLabel: String? = null,
    look: MuteLook = MuteLook.ON,
    detail: String? = null,
    icon: @Composable (Color) -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val (fill, tint) = when (look) {
        MuteLook.ON -> colour.copy(alpha = 0.18f) to colour
        MuteLook.MUTED_THIS_TRIP -> Color.Transparent to colour
        MuteLook.OFF -> colour to scheme.surface
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(76.dp)
            .clip(MaterialTheme.shapes.medium)
            .combinedClickable(
                role = Role.Button,
                onClick = onClick,
                onLongClick = onLongClick,
                onLongClickLabel = onLongClickLabel,
            )
            .semantics(mergeDescendants = true) { contentDescription = description }
            .padding(vertical = 6.dp),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(fill)
                .then(
                    if (look == MuteLook.MUTED_THIS_TRIP) Modifier.border(1.5.dp, colour, CircleShape) else Modifier,
                ),
        ) { icon(tint) }
        Text(
            caption,
            color = scheme.onSurfaceVariant,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            lineHeight = 14.sp,
            maxLines = 2,
            modifier = Modifier.padding(top = 4.dp),
        )
        if (detail != null) {
            Text(
                detail,
                color = scheme.onSurfaceVariant.copy(alpha = 0.75f),
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                lineHeight = 13.sp,
                maxLines = 2,
            )
        }
    }
}
