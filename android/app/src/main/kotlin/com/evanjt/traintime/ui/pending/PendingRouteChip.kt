package com.evanjt.traintime.ui.pending

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.PendingRoute
import com.evanjt.traintime.notify.NotifyPlan
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val TIME = DateTimeFormatter.ofPattern("HH:mm")

@Composable
private fun countdownText(depTs: Long, now: Long): String {
    val mins = ((depTs - now) / 60).coerceAtLeast(0)
    return if (mins >= 60) {
        stringResource(CoreR.string.in_h_min_fmt, (mins / 60).toInt(), (mins % 60).toInt())
    } else {
        stringResource(CoreR.string.in_min_fmt, mins.toInt())
    }
}

// Queued shared route: destination, departure countdown, discard. Tap runs
// the resume check (prompts when the train is on the board).
@Composable
fun PendingRouteChip(
    route: PendingRoute,
    nowEpochSeconds: Long,
    plan: NotifyPlan?,
    onTap: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val leg = route.currentLeg ?: return
    val palette = LocalAppPalette.current
    var confirmDiscard by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
        shape = MaterialTheme.shapes.medium,
        tonalElevation = 3.dp,
    ) {
        Row(
            Modifier.clickable(onClick = onTap).padding(start = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                Text(
                    stringResource(CoreR.string.route_to_fmt, route.finalDestination),
                    style = MaterialTheme.typography.titleSmall,
                )
                val lineLabel = "${leg.category ?: ""}${leg.lineNumber ?: ""}"
                val depTime = TIME.format(Instant.ofEpochSecond(leg.depTs).atZone(ZoneId.of("Europe/Zurich")))
                Text(
                    stringResource(R.string.departs_fmt, lineLabel, depTime) + " · " +
                        countdownText(leg.depTs, nowEpochSeconds),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (plan != null && plan.notifyTs > nowEpochSeconds) {
                    val mins = (plan.notifyTs - nowEpochSeconds) / 60
                    val walk = plan.walkMin
                    Text(
                        // Colour the calculated walk time and the fixed buffer
                        // distinctly, so "in 21 min" isn't mistaken for their sum.
                        if (walk != null) {
                            val notifiedIn = stringResource(R.string.notified_in_fmt, mins.toInt())
                            val walkText = stringResource(R.string.walk_min_fmt, walk)
                            val bufferText = stringResource(R.string.buffer_fmt, plan.bufferMin)
                            buildAnnotatedString {
                                withStyle(SpanStyle(color = palette.ahead)) { append(notifiedIn) }
                                append("  (~")
                                withStyle(SpanStyle(color = palette.platform)) { append(walkText) }
                                append(" + ")
                                withStyle(SpanStyle(color = palette.amber)) { append(bufferText) }
                                append(")")
                            }
                        } else {
                            val notifiedIn = stringResource(R.string.youll_be_notified_in_fmt, mins.toInt())
                            buildAnnotatedString {
                                withStyle(SpanStyle(color = palette.ahead)) { append(notifiedIn) }
                            }
                        },
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            IconButton(onClick = { confirmDiscard = true }) {
                Icon(Icons.Default.Close, contentDescription = stringResource(R.string.discard_route_cd))
            }
        }
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(R.string.discard_route_title)) },
            text = { Text(stringResource(R.string.discard_route_body_fmt, route.finalDestination)) },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onDismiss() }) { Text(stringResource(R.string.discard)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDiscard = false }) { Text(stringResource(R.string.keep)) }
            },
        )
    }
}
