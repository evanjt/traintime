package com.evanjt.traintime.ui.onboarding

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette

// A small anchored coach-mark, not a full-screen card. Title and body only: the
// Back/Skip/Next controls live in a fixed bar (TourNavBar) so they never move.
// The caret hints at the spotlighted feature; the host places the bubble in the
// screen half opposite the target so it never covers what it explains.
@Composable
fun CalloutBubble(
    title: String,
    body: String,
    caretUp: Boolean,
    modifier: Modifier = Modifier,
) {
    val bubbleColor = MaterialTheme.colorScheme.surfaceContainerHigh
    val bubbleBorder = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
    Column(
        modifier = modifier.widthIn(max = 380.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (caretUp) Caret(up = true, color = bubbleColor)

        Surface(
            shape = RoundedCornerShape(16.dp),
            color = bubbleColor,
            border = bubbleBorder,
            shadowElevation = 8.dp,
        ) {
            Column(Modifier.padding(horizontal = 18.dp, vertical = 16.dp)) {
                Text(
                    title,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.size(6.dp))
                Text(
                    body,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 14.sp,
                )
            }
        }

        if (!caretUp) Caret(up = false, color = bubbleColor)
    }
}

// The tour's fixed navigation bar: progress dots + Back / Skip / Next, pinned to
// the bottom so the controls stay in the same place on every page. The Back slot
// keeps its width when hidden so Next never shifts.
@Composable
fun TourNavBar(
    index: Int,
    total: Int,
    onBack: () -> Unit,
    onSkip: () -> Unit,
    onNext: () -> Unit,
    nextLabel: String,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)),
        shadowElevation = 8.dp,
    ) {
        Row(
            Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(64.dp)) {
                if (index > 0) TextButton(onClick = onBack) { Text("Back") }
            }
            Row(
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .weight(1f)
                    .clearAndSetSemantics { contentDescription = "Step ${index + 1} of $total" },
            ) {
                repeat(total) { i ->
                    val active = i == index
                    Box(
                        Modifier
                            .padding(horizontal = 3.dp)
                            .size(if (active) 8.dp else 6.dp)
                            .background(
                                if (active) palette.platform else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                                CircleShape,
                            ),
                    )
                }
            }
            TextButton(onClick = onSkip) {
                Text("Skip", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Button(onClick = onNext) { Text(nextLabel) }
        }
    }
}

// A simple triangle caret drawn with a rotated square, pointing toward the target.
@Composable
private fun Caret(up: Boolean, color: Color) {
    androidx.compose.foundation.Canvas(
        modifier = Modifier
            .padding(vertical = 2.dp)
            .size(width = 18.dp, height = 9.dp),
    ) {
        val path = androidx.compose.ui.graphics.Path().apply {
            if (up) {
                moveTo(size.width / 2f, 0f)
                lineTo(size.width, size.height)
                lineTo(0f, size.height)
            } else {
                moveTo(0f, 0f)
                lineTo(size.width, 0f)
                lineTo(size.width / 2f, size.height)
            }
            close()
        }
        drawPath(path, color)
    }
}
