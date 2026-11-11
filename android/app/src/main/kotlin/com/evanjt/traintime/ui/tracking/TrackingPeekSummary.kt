package com.evanjt.traintime.ui.tracking

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.linePill
import com.evanjt.traintime.ui.MainViewModel
import kotlinx.coroutines.delay

// The tracking card at Peek: line, destination, countdown and platform, in the
// strip the board leaves. The top stays clear for the card's x.
@Composable
fun TrackingPeekSummary(focused: FocusedDeparture?, mode: TransportMode, nowSeconds: Long) {
    val palette = LocalAppPalette.current
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier.fillMaxSize().padding(start = 12.dp, end = 12.dp, top = 56.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (focused == null) return@Column
        if (focused.lineNumber.isNotEmpty()) {
            Text(
                focused.lineNumber,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .clip(RoundedCornerShape(7.dp))
                    .background(palette.linePill(focused.lineNumber, mode))
                    .padding(horizontal = 8.dp, vertical = 3.dp),
            )
        }
        Text(
            focused.destination,
            color = if (focused.platformChanged) palette.platformChangedOrange else MaterialTheme.colorScheme.onSurface,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            focused.countdownText(
                nowSeconds,
                stringResource(CoreR.string.departed),
                stringResource(CoreR.string.row_now),
            ),
            color = if (focused.effectiveMinutesUntil(nowSeconds) < -0.5) secondary else palette.minutesSoon,
            fontSize = 36.sp,
            fontWeight = FontWeight.Bold,
        )
        if (focused.delay > 0) {
            Text("+${focused.delay}", color = palette.delay, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
        if (focused.platform.isNotEmpty()) {
            Text(
                stringResource(R.string.platform_full_fmt, focused.platform),
                color = if (focused.platformChanged) palette.platformChangedOrange else secondary,
                fontSize = 13.sp,
            )
        }
    }
}

// The live Peek card. The session is still on screen, so it keeps the screen
// awake and handles Back as the full tracking screen does.
@Composable
fun TrackingPeek(viewModel: MainViewModel, onBack: () -> Unit) {
    val view = LocalView.current
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
    BackHandler(onBack = onBack)
    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) {
        while (true) {
            nowSeconds = System.currentTimeMillis() / 1000
            delay(250)
        }
    }
    TrackingPeekSummary(viewModel.focusedTrain, viewModel.currentMode, nowSeconds)
}
