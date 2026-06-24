package com.evanjt.traintime.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import com.evanjt.traintime.ui.station.icon

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(viewModel: MainViewModel, onDismiss: () -> Unit) {
    val palette = LocalAppPalette.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 32.dp)) {
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

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            ) {
                Text("Version", color = onSurface)
                Spacer(Modifier.weight(1f))
                Text(BuildConfig.VERSION_NAME, color = secondary)
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
        }
    }
}

private val appearanceOptions = listOf(
    "system" to "System",
    "light" to "Light",
    "dark" to "Dark",
)
