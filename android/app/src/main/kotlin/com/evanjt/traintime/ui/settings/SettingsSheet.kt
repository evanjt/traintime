package com.evanjt.traintime.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.evanjt.traintime.BuildConfig
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.review.ReviewLauncher
import com.evanjt.traintime.ui.MainViewModel
import com.evanjt.traintime.ui.PhoneWatchType

@OptIn(ExperimentalMaterial3Api::class)
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
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        // Opened via the header watch icon → straight onto the watch page.
        var page by remember {
            mutableStateOf(if (focusWatch) SettingsPage.WATCH else SettingsPage.MAIN)
        }
        // System back leaves a sub-page before it can dismiss the sheet.
        BackHandler(enabled = page != SettingsPage.MAIN) { page = SettingsPage.MAIN }
        LaunchedEffect(Unit) { viewModel.refreshWatchLinks() }
        if (page == SettingsPage.FAVOURITES) {
            FavouritesPage(viewModel = viewModel, onBack = { page = SettingsPage.MAIN })
            return@ModalBottomSheet
        }
        if (page == SettingsPage.WATCH) {
            WatchPage(viewModel = viewModel, onBack = { page = SettingsPage.MAIN })
            return@ModalBottomSheet
        }
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
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 16.dp).align(Alignment.CenterHorizontally),
            )

            SegmentedSetting(
                label = "Default Mode",
                options = TransportMode.entries.map { it.label },
                selectedIndex = TransportMode.entries.indexOf(viewModel.defaultMode),
                onSelect = { viewModel.updateDefaultMode(TransportMode.entries[it]) },
            )

            val appearanceMode by viewModel.prefs.appearanceMode.collectAsState(initial = "system")
            SegmentedSetting(
                label = "Appearance",
                options = appearanceOptions.map { it.second },
                selectedIndex = appearanceOptions.indexOfFirst { it.first == appearanceMode }.coerceAtLeast(0),
                onSelect = { viewModel.updateAppearanceMode(appearanceOptions[it].first) },
                modifier = Modifier.padding(top = 16.dp),
            )

            ReminderSettings(viewModel = viewModel, modifier = Modifier.padding(top = 16.dp))

            if (viewModel.favouritesList.isNotEmpty()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { page = SettingsPage.FAVOURITES }
                        .padding(top = 16.dp),
                ) {
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = null,
                        tint = palette.favouriteStar,
                        modifier = Modifier.size(20.dp),
                    )
                    Text("Favourites", color = onSurface, modifier = Modifier.padding(start = 12.dp))
                    Spacer(Modifier.weight(1f))
                    Text("${viewModel.favouritesList.size}", color = secondary)
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = secondary,
                    )
                }
            }

            // Watch link, one row: the connected watch (or count), details on the page.
            // Hidden entirely when no watch is paired (Wear or Garmin).
            if (viewModel.watchLinks.isNotEmpty()) {
                val connected = viewModel.watchLinks.filter { it.connected }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { page = SettingsPage.WATCH }
                        .padding(top = 16.dp),
                ) {
                    Icon(Icons.Filled.Watch, contentDescription = null, tint = secondary, modifier = Modifier.size(20.dp))
                    Text("Watch link", color = onSurface, modifier = Modifier.padding(start = 12.dp))
                    Spacer(Modifier.weight(1f))
                    Text(
                        when (connected.size) {
                            0 -> "Not connected"
                            1 -> connected.first().name
                            else -> "${connected.size} connected"
                        },
                        color = if (connected.isEmpty()) secondary else palette.platform,
                        fontSize = 14.sp,
                    )
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = secondary,
                    )
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
                    .clickable { activity?.let { ReviewLauncher.openStoreListing(it) } }
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

private val savedLeadOptions = listOf(5, 10, 15, 30)
private val connectionLeadOptions = listOf(2, 3, 4, 5)

// Route-reminder controls: permission status, the two independent leads, and a
// test notification so the user (or a debugger) can confirm delivery without a
// real departure > 15 min out.
@Composable
private fun ReminderSettings(viewModel: MainViewModel, modifier: Modifier = Modifier) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val palette = LocalAppPalette.current
    val context = LocalContext.current

    val routeLead by viewModel.prefs.routeReminderLeadMinutes.collectAsState(initial = 15)
    val connectionLead by viewModel.prefs.connectionReminderLeadMinutes.collectAsState(initial = 3)
    val distanceAware by viewModel.prefs.distanceAwareReminder.collectAsState(initial = false)
    val backgroundTracking by viewModel.prefs.backgroundReminderTracking.collectAsState(initial = true)

    // Re-check on resume so returning from system settings updates the row.
    var granted by remember { mutableStateOf(notificationsEnabled(context)) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) granted = notificationsEnabled(context)
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Column(modifier) {
        Text("Route reminders", color = secondary, fontSize = 13.sp)

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .let { if (granted) it else it.clickable { openNotificationSettings(context) } }
                .padding(top = 8.dp),
        ) {
            Text("Notifications", color = onSurface)
            Spacer(Modifier.weight(1f))
            Text(
                if (granted) "Allowed" else "Turn on",
                color = if (granted) secondary else palette.platform,
                fontSize = 14.sp,
            )
        }

        SegmentedSetting(
            label = "Remind me before departure",
            options = savedLeadOptions.map { "$it min" },
            selectedIndex = savedLeadOptions.indexOf(routeLead).coerceAtLeast(0),
            onSelect = { viewModel.setRouteReminderLead(savedLeadOptions[it]) },
            modifier = Modifier.padding(top = 12.dp),
        )

        SegmentedSetting(
            label = "Before a connection",
            options = connectionLeadOptions.map { "$it min" },
            selectedIndex = connectionLeadOptions.indexOf(connectionLead).coerceAtLeast(0),
            onSelect = { viewModel.setConnectionReminderLead(connectionLeadOptions[it]) },
            modifier = Modifier.padding(top = 12.dp),
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text("Adjust for distance to station", color = onSurface)
                Text("Lead becomes your walk time + the minutes above", color = secondary, fontSize = 12.sp)
            }
            Switch(checked = distanceAware, onCheckedChange = { viewModel.setDistanceAwareReminder(it) })
        }

        if (distanceAware) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Update in the background", color = onSurface)
                    Text("Keep it accurate as you move, even when the app is closed", color = secondary, fontSize = 12.sp)
                }
                Switch(checked = backgroundTracking, onCheckedChange = { viewModel.setBackgroundReminderTracking(it) })
            }
        }

        Text(
            if (distanceAware) {
                "You'll be notified your walk time + $routeLead min before departure"
            } else {
                "You'll be notified $routeLead min before departure"
            },
            color = palette.platform,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 12.dp),
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { viewModel.sendTestNotification() }
                .padding(top = 12.dp),
        ) {
            Text("Send test notification", color = onSurface)
        }

        if (distanceAware) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.sendDistanceReminderTest() }
                    .padding(top = 12.dp),
            ) {
                Text("Test distance reminder", color = onSurface)
            }
        }
    }
}

private fun notificationsEnabled(context: android.content.Context): Boolean =
    if (android.os.Build.VERSION.SDK_INT >= 33) {
        ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    } else {
        NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

private fun openNotificationSettings(context: android.content.Context) {
    context.startActivity(
        android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName),
    )
}

private enum class SettingsPage { MAIN, FAVOURITES, WATCH }

@Composable
private fun WatchPage(viewModel: MainViewModel, onBack: () -> Unit) {
    val palette = LocalAppPalette.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = onSurface)
            }
            Text(
                "Watch link",
                color = onSurface,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        // Every device paired in Garmin Connect (plus Wear watches) with live status.
        // The phone only ever messages connected watches with TrainTime installed.
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
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp),
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

// One-line setting: label above a full-width segmented row, every option a
// tile of equal width so the group spans edge to edge of the sheet content.
@Composable
private fun SegmentedSetting(
    label: String,
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = 8.dp)) {
            options.forEachIndexed { index, option ->
                SegmentedButton(
                    selected = index == selectedIndex,
                    onClick = { onSelect(index) },
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                    // No checkmark: four labelled tiles need the width.
                    icon = {},
                    modifier = Modifier.weight(1f),
                ) {
                    Text(option, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun FavouritesPage(viewModel: MainViewModel, onBack: () -> Unit) {
    val palette = LocalAppPalette.current
    val onSurface = MaterialTheme.colorScheme.onSurface
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = onSurface)
            }
            Text(
                "Favourites",
                color = onSurface,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (viewModel.favouritesList.isEmpty()) {
            Text(
                "No favourites yet",
                color = secondary,
                fontSize = 14.sp,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
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
}
