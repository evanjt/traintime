package com.evanjt.traintime.ui.station

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.linePill

@Composable
fun DepartureRow(
    departure: Departure,
    isFavourite: Boolean,
    mode: TransportMode,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    // A cancelled train will never run: the label takes the minutes and delay
    // slots, and the rest of the row is dimmed with the destination struck.
    val dimmed = !departure.isSelectable
    val minutesColor = when {
        dimmed -> secondary
        departure.minutesUntil <= 2 -> palette.minutesNow
        else -> palette.minutesSoon
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .semantics { this.selected = selected }
            .background(
                when {
                    // The board's selected treatment, as on the mode picker.
                    selected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                    isFavourite -> palette.favouriteBackground
                    else -> Color.Transparent
                },
            )
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        if (departure.cancelled) {
            Box(Modifier.width(92.dp), contentAlignment = Alignment.CenterEnd) {
                Text(
                    stringResource(CoreR.string.row_cancelled),
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    modifier = Modifier
                        .background(palette.delay, RoundedCornerShape(6.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        } else {
            Text(
                departure.minutesLabel(LocalContext.current),
                color = minutesColor,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                textAlign = TextAlign.End,
                modifier = Modifier.width(50.dp),
            )

            Spacer(Modifier.width(8.dp))

            Box(Modifier.width(34.dp)) {
                if (departure.delay > 0 && !dimmed) {
                    Text(
                        "+${departure.delay}",
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .background(palette.delay, CircleShape)
                            .padding(horizontal = 5.dp, vertical = 2.dp),
                    )
                }
            }
        }

        Spacer(Modifier.width(8.dp))

        // Line number as a filled pill, kept in a fixed slot so destinations
        // still align down the column.
        Box(Modifier.width(52.dp), contentAlignment = Alignment.CenterStart) {
            if (departure.lineNumber.isNotEmpty()) {
                Text(
                    departure.lineNumber,
                    color = if (dimmed) secondary else Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(
                            if (dimmed) {
                                MaterialTheme.colorScheme.surfaceVariant
                            } else {
                                palette.linePill(departure.lineNumber, mode)
                            },
                        )
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }

        Spacer(Modifier.width(10.dp))

        Text(
            departure.destination,
            color = if (dimmed) secondary else MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.Medium,
            textDecoration = if (departure.cancelled) TextDecoration.LineThrough else null,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )

        if (isFavourite) {
            Icon(
                Icons.Filled.Star,
                contentDescription = null,
                tint = palette.favouriteStar,
                modifier = Modifier.size(16.dp).padding(start = 4.dp),
            )
        }

        if (departure.isSelectable) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = secondary,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
    }
}
