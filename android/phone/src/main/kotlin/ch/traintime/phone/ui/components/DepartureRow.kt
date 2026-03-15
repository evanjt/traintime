package ch.traintime.phone.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ch.traintime.shared.AppColors
import ch.traintime.shared.models.Departure

@Composable
fun DepartureRow(departure: Departure, onTap: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !departure.isGone, onClick = onTap)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Minutes
        Text(
            text = departure.minutesText,
            fontSize = if (departure.minutesUntil <= 0) 14.sp else 18.sp,
            fontWeight = FontWeight.Bold,
            color = minutesColor(departure),
            modifier = Modifier.width(50.dp),
            maxLines = 1
        )

        // Delay
        Text(
            text = if (departure.delay > 0 && !departure.isGone) "+${departure.delay}" else "",
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = Color(AppColors.DELAY),
            modifier = Modifier.width(24.dp)
        )

        // Line number or platform
        Box(modifier = Modifier.width(36.dp)) {
            if (departure.lineNumber.isNotEmpty()) {
                Text(
                    text = departure.lineNumber,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (departure.isGone) Color.Gray else Color(AppColors.PLATFORM)
                )
            } else if (departure.platform.isNotEmpty()) {
                val text = "P${departure.platform}"
                if (departure.isGone) {
                    Text(text = text, fontSize = 12.sp, color = Color.Gray)
                } else if (departure.platformChanged) {
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = Color(AppColors.PLATFORM_CHANGED)
                    ) {
                        Text(
                            text = text,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White,
                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
                        )
                    }
                } else {
                    Text(text = text, fontSize = 12.sp, color = Color(AppColors.PLATFORM))
                }
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Destination
        Text(
            text = departure.destination,
            fontSize = 16.sp,
            color = if (departure.isGone) Color.Gray else Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )

        // Chevron
        if (!departure.isGone) {
            Text(text = "\u203A", fontSize = 16.sp, color = Color.Gray.copy(alpha = 0.5f))
        }
    }
}

private fun minutesColor(departure: Departure): Color {
    if (departure.isGone) return Color.Gray
    if (departure.minutesUntil <= 2) return Color(AppColors.MINUTES_NOW)
    return Color(AppColors.MINUTES_SOON)
}
