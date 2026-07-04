package com.evanjt.traintime.ui.settings

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.BuildConfig
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.review.ReviewLauncher
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.PhoneWatchType
import com.evanjt.traintime.ui.station.icon

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SettingsSheet(
    viewModel: MainViewModel,
    focusWatch: Boolean = false,
    onOpenAttribution: () -> Unit,
    onDismiss: () -> Unit,
) {
    val palette = LocalAppPalette.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val watchRequester = remember { BringIntoViewRequester() }
    // When opened via the header watch icon, scroll straight to the Watch link section.
    LaunchedEffect(focusWatch, viewModel.watchLinks.size) {
        if (focusWatch && viewModel.watchLinks.isNotEmpty()) watchRequester.bringIntoView()
    }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                "Settings",
                color = onSurface,
                fontSize = 18.sp,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 16.dp).align(Alignment.CenterHorizontally),
            )

            Text("Default Mode", color = secondary, fontSize = 13.sp)
            TransportMode.entries.forEach { mode ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.updateDefaultMode(mode) }
                        .padding(vertical = 10.dp),
                ) {
                    Icon(mode.icon, contentDescription = null, tint = secondary, modifier = Modifier.size(20.dp))
                    Text(mode.label, color = onSurface, modifier = Modifier.padding(start = 12.dp))
                    Spacer(Modifier.weight(1f))
                    if (viewModel.defaultMode == mode) {
                        Icon(Icons.Filled.Check, contentDescription = "Selected", tint = palette.platform)
                    }
                }
            }

            val appearanceMode by viewModel.prefs.appearanceMode.collectAsState(initial = "system")
            Text("Appearance", color = secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 16.dp))
            appearanceOptions.forEach { (value, label) ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.updateAppearanceMode(value) }
                        .padding(vertical = 10.dp),
                ) {
                    Text(label, color = onSurface)
                    Spacer(Modifier.weight(1f))
                    if (appearanceMode == value) {
                        Icon(Icons.Filled.Check, contentDescription = "Selected", tint = palette.platform)
                    }
                }
            }

            if (viewModel.favouritesList.isNotEmpty()) {
                Text(
                    "Favourites (${viewModel.favouritesList.size})",
                    color = secondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 16.dp),
                )
                viewModel.favouritesList.forEach { fav ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Icon(
                            Icons.Filled.Star,
                            contentDescription = null,
                            tint = palette.favouriteStar,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            fav.displayString,
                            color = onSurface,
                            fontSize = 14.sp,
                            modifier = Modifier.padding(start = 10.dp).weight(1f),
                        )
                        IconButton(onClick = { viewModel.removeFavourite(fav) }) {
                            Icon(Icons.Filled.Delete, contentDescription = "Remove", tint = secondary)
                        }
                    }
                }
            }

            // Watch link status — only shown when a watch is paired (Wear or Garmin),
            // so nothing appears when no connection is possible.
            LaunchedEffect(Unit) { viewModel.refreshWatchLinks() }
            if (viewModel.watchLinks.isNotEmpty()) {
              Column(Modifier.bringIntoViewRequester(watchRequester)) {
                Text("Watch link", color = secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 16.dp))
                viewModel.watchLinks.forEach { link ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    ) {
                        Icon(Icons.Filled.Watch, contentDescription = null, tint = secondary, modifier = Modifier.size(20.dp))
                        Text(link.name, color = onSurface, modifier = Modifier.padding(start = 12.dp))
                        Spacer(Modifier.weight(1f))
                        Text(
                            if (link.connected) "Connected" else "Not connected",
                            color = if (link.connected) palette.platform else secondary,
                            fontSize = 13.sp,
                        )
                    }
                }

                // Mirror phone state + location to the watch (Garmin only). The header
                // watch icon launches the app on the watch on demand.
                if (viewModel.watchLinks.any { it.type == PhoneWatchType.GARMIN }) {
                    val mirror by viewModel.prefs.mirrorToWatch.collectAsState(initial = true)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Mirror to watch", color = onSurface)
                            Text("Send your tracked train, mode, station and location to the watch", color = secondary, fontSize = 12.sp)
                        }
                        Switch(checked = mirror, onCheckedChange = { viewModel.setMirrorToWatch(it) })
                    }
                }
              }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            ) {
                Text("Version", color = onSurface)
                Spacer(Modifier.weight(1f))
                Text(BuildConfig.VERSION_NAME, color = secondary)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        viewModel.replayOnboarding()
                        onDismiss()
                    }
                    .padding(top = 16.dp),
            ) {
                Text("Replay walkthrough", color = onSurface)
            }

            val activity = LocalContext.current as? android.app.Activity
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { activity?.let { ReviewLauncher.launch(it) } }
                    .padding(top = 16.dp, bottom = 4.dp),
            ) {
                Text("Rate this app", color = onSurface)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenAttribution() }
                    .padding(top = 16.dp),
            ) {
                Text("Attribution", color = onSurface)
            }
        }
    }
}

private val appearanceOptions = listOf(
    "system" to "System",
    "light" to "Light",
    "dark" to "Dark",
)
