package com.evanjt.traintime.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette

// A small anchored coach-mark, not a full-screen card. The caret hints at the
// spotlighted feature; the bubble itself is placed in the screen half opposite
// the target by the host, so it never sits over what it explains.
@Composable
fun CalloutBubble(
    title: String,
    body: String,
    index: Int,
    total: Int,
    caretUp: Boolean,
    onBack: () -> Unit,
    onSkip: () -> Unit,
    onNext: () -> Unit,
    nextLabel: String,
    modifier: Modifier = Modifier,
) {
    val palette = LocalAppPalette.current
    Column(
        modifier = modifier.widthIn(max = 380.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (caretUp) Caret(up = true, color = MaterialTheme.colorScheme.surface)

        Surface(
            shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 3.dp,
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
                Spacer(Modifier.size(14.dp))

                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    if (index > 0) {
                        TextButton(onClick = onBack) { Text("Back") }
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.weight(1f),
                    ) {
                        repeat(total) { i ->
                            val active = i == index
                            Box(
                                Modifier
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
                    Spacer(Modifier.size(4.dp))
                    Button(onClick = onNext) { Text(nextLabel) }
                }
            }
        }

        if (!caretUp) Caret(up = false, color = MaterialTheme.colorScheme.surface)
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
