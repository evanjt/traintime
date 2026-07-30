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
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.AlertDialog
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
import androidx.compose.material3.TextButton
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
import androidx.appcompat.app.AppCompatDelegate
import androidx.activity.compose.LocalActivity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.core.os.LocaleListCompat
import com.evanjt.traintime.BuildConfig
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.core.R as CoreR
import com.evanjt.traintime.data.model.TransportMode
import com.evanjt.traintime.review.ReviewLauncher
import com.evanjt.traintime.session.TrackingNotificationService
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
        if (page == SettingsPage.HELP) {
            TrackingHelpPage(onBack = { page = SettingsPage.MAIN })
            return@ModalBottomSheet
        }
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                stringResource(CoreR.string.settings),
                color = onSurface,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 16.dp).align(Alignment.CenterHorizontally),
            )

            SegmentedSetting(
                label = stringResource(CoreR.string.default_mode),
                options = TransportMode.entries.map { stringResource(it.labelRes) },
                selectedIndex = TransportMode.entries.indexOf(viewModel.defaultMode),
                onSelect = { viewModel.updateDefaultMode(TransportMode.entries[it]) },
            )

            val appearanceMode by viewModel.prefs.appearanceMode.collectAsState(initial = "system")
            SegmentedSetting(
                label = stringResource(R.string.appearance),
                options = appearanceOptions.map { stringResource(it.second) },
                selectedIndex = appearanceOptions.indexOfFirst { it.first == appearanceMode }.coerceAtLeast(0),
                onSelect = { viewModel.updateAppearanceMode(appearanceOptions[it].first) },
                modifier = Modifier.padding(top = 16.dp),
            )

            // In-app language. AppCompatDelegate applies and persists the
            // choice (recreating the activity); the AppPrefs copy reaches the
            // widget and notification processes, which appcompat cannot.
            val currentTag = AppCompatDelegate.getApplicationLocales()
                .toLanguageTags().substringBefore(",").substringBefore("-")
            SegmentedSetting(
                label = stringResource(R.string.language),
                options = languageOptions.map { it.second },
                selectedIndex = languageOptions.indexOfFirst { it.first == currentTag }.coerceAtLeast(0),
                onSelect = {
                    val tag = languageOptions[it].first
                    viewModel.updateAppLanguage(tag)
                    AppCompatDelegate.setApplicationLocales(
                        LocaleListCompat.forLanguageTags(tag),
                    )
                },
                modifier = Modifier.padding(top = 16.dp),
            )

            ReminderSettings(viewModel = viewModel, modifier = Modifier.padding(top = 16.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { page = SettingsPage.HELP }
                    .padding(top = 16.dp),
            ) {
                Icon(
                    Icons.Filled.Info,
                    contentDescription = null,
                    tint = secondary,
                    modifier = Modifier.size(20.dp),
                )
                Text(stringResource(R.string.help_title), color = onSurface, modifier = Modifier.padding(start = 12.dp))
                Spacer(Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = secondary)
            }

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
                    Text(stringResource(CoreR.string.favourites), color = onSurface, modifier = Modifier.padding(start = 12.dp))
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
                    Text(stringResource(R.string.watch_link), color = onSurface, modifier = Modifier.padding(start = 12.dp))
                    Spacer(Modifier.weight(1f))
                    Text(
                        when (connected.size) {
                            0 -> stringResource(CoreR.string.not_connected)
                            1 -> connected.first().name
                            else -> stringResource(R.string.n_connected_fmt, connected.size)
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
                Text(stringResource(R.string.version), color = onSurface)
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
                Text(stringResource(R.string.replay_walkthrough), color = onSurface)
            }

            val activity = LocalActivity.current
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { activity?.let { ReviewLauncher.openStoreListing(it) } }
                    .padding(top = 16.dp, bottom = 4.dp),
            ) {
                Text(stringResource(R.string.rate_this_app), color = onSurface)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenAttribution() }
                    .padding(top = 16.dp),
            ) {
                Text(stringResource(R.string.attribution), color = onSurface)
            }
        }
    }
}

private val appearanceOptions = listOf(
    "system" to R.string.opt_system,
    "light" to R.string.opt_light,
    "dark" to R.string.opt_dark,
)

// "" = follow the system language. "Auto" reads the same in all four
// languages, so five options still fit one segmented row.
private val languageOptions = listOf(
    "" to "Auto",
    "en" to "EN",
    "de" to "DE",
    "fr" to "FR",
    "it" to "IT",
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
    val distanceAware by viewModel.prefs.distanceAwareReminder.collectAsState(initial = true)
    val backgroundTracking by viewModel.prefs.backgroundReminderTracking.collectAsState(initial = true)
    val alertBeforeDeparture by viewModel.prefs.alertBeforeDeparture.collectAsState(initial = true)

    var confirmBgOff by remember { mutableStateOf(false) }

    // Re-check on resume so returning from system settings updates the row.
    var granted by remember { mutableStateOf(notificationsEnabled(context)) }
    var channelsOn by remember { mutableStateOf(trackingChannelsEnabled(context)) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                granted = notificationsEnabled(context)
                channelsOn = trackingChannelsEnabled(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Column(modifier) {
        Text(stringResource(R.string.route_reminders), color = secondary, fontSize = 13.sp)

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .let {
                    if (granted && channelsOn) it else it.clickable { openNotificationSettings(context) }
                }
                .padding(top = 8.dp),
        ) {
            Text(stringResource(R.string.notifications), color = onSurface)
            Spacer(Modifier.weight(1f))
            // A muted tracking channel is invisible to the app-level grant, so
            // report it rather than claiming everything is allowed.
            Text(
                when {
                    !granted -> stringResource(R.string.turn_on)
                    !channelsOn -> stringResource(R.string.notifications_blocked)
                    else -> stringResource(R.string.allowed)
                },
                color = if (granted && channelsOn) secondary else palette.platform,
                fontSize = 14.sp,
            )
        }

        SegmentedSetting(
            label = stringResource(R.string.remind_before_departure),
            options = savedLeadOptions.map { stringResource(R.string.n_min_fmt, it) },
            selectedIndex = savedLeadOptions.indexOf(routeLead).coerceAtLeast(0),
            onSelect = { viewModel.setRouteReminderLead(savedLeadOptions[it]) },
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            stringResource(R.string.remind_before_departure_desc),
            color = secondary,
            fontSize = 12.sp,
        )

        SegmentedSetting(
            label = stringResource(R.string.before_a_connection),
            options = connectionLeadOptions.map { stringResource(R.string.n_min_fmt, it) },
            selectedIndex = connectionLeadOptions.indexOf(connectionLead).coerceAtLeast(0),
            onSelect = { viewModel.setConnectionReminderLead(connectionLeadOptions[it]) },
            modifier = Modifier.padding(top = 12.dp),
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.adjust_distance), color = onSurface)
                Text(stringResource(R.string.adjust_distance_desc), color = secondary, fontSize = 12.sp)
            }
            Switch(checked = distanceAware, onCheckedChange = { viewModel.setDistanceAwareReminder(it) })
        }

        // Governs the whole live session, not just a saved route's reminder, so
        // it stands on its own rather than hiding behind the distance toggle.
        // Switching it off takes tracking away entirely once the app closes, so
        // it is confirmed rather than silently applied.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.update_background), color = onSurface)
                Text(stringResource(R.string.update_background_desc), color = secondary, fontSize = 12.sp)
            }
            Switch(
                checked = backgroundTracking,
                onCheckedChange = {
                    if (it) viewModel.setBackgroundReminderTracking(true) else confirmBgOff = true
                },
            )
        }

        if (confirmBgOff) {
            AlertDialog(
                onDismissRequest = { confirmBgOff = false },
                title = { Text(stringResource(R.string.bg_off_warning_title)) },
                text = { Text(stringResource(R.string.bg_off_warning_body)) },
                confirmButton = {
                    TextButton(onClick = {
                        confirmBgOff = false
                        viewModel.setBackgroundReminderTracking(false)
                    }) { Text(stringResource(R.string.bg_off_warning_confirm)) }
                },
                dismissButton = {
                    TextButton(onClick = { confirmBgOff = false }) {
                        Text(stringResource(CoreR.string.review_not_now))
                    }
                },
            )
        }

        Text(
            if (distanceAware) {
                stringResource(R.string.notify_walk_plus_fmt, routeLead)
            } else {
                stringResource(R.string.notify_lead_fmt, routeLead)
            },
            color = palette.platform,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 12.dp),
        )

        // Applies to a live background-tracking session: a one-off leave heads-up
        // as departure nears, on top of the always-on tracking card.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.alert_before_departure), color = onSurface)
                Text(stringResource(R.string.alert_before_departure_desc), color = secondary, fontSize = 12.sp)
            }
            Switch(checked = alertBeforeDeparture, onCheckedChange = { viewModel.setAlertBeforeDeparture(it) })
        }

        if (distanceAware) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.sendDistanceReminderTest() }
                    .padding(top = 12.dp),
            ) {
                Text(stringResource(R.string.test_distance_reminder), color = onSurface)
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

// The app-level grant says nothing about a channel the user muted by hand, and
// the tracking card and the leave alert each live on their own channel.
private fun trackingChannelsEnabled(context: android.content.Context): Boolean {
    if (android.os.Build.VERSION.SDK_INT < 26) return true
    val manager = context.getSystemService(android.app.NotificationManager::class.java) ?: return true
    return TrackingNotificationService.CHANNEL_IDS.all { id ->
        val channel = manager.getNotificationChannel(id)
        channel == null || channel.importance != android.app.NotificationManager.IMPORTANCE_NONE
    }
}

private fun openNotificationSettings(context: android.content.Context) {
    context.startActivity(
        android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName),
    )
}

private enum class SettingsPage { MAIN, FAVOURITES, WATCH, HELP }

// Plain-language explainer for background tracking, so the proximity tiering,
// the leave alert and the OEM battery caveat aren't a mystery.
@Composable
private fun TrackingHelpPage(onBack: () -> Unit) {
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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(CoreR.string.back), tint = onSurface)
            }
            Text(
                stringResource(R.string.help_title),
                color = onSurface,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        val points = listOf(
            R.string.help_countdown_h to R.string.help_countdown_b,
            R.string.help_cadence_h to R.string.help_cadence_b,
            R.string.help_battery_h to R.string.help_battery_b,
            R.string.help_leave_h to R.string.help_leave_b,
            R.string.help_oem_h to R.string.help_oem_b,
        )
        points.forEach { (heading, body) ->
            Column(Modifier.fillMaxWidth().padding(top = 14.dp)) {
                Text(stringResource(heading), color = onSurface, fontWeight = FontWeight.SemiBold)
                Text(stringResource(body), color = secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 2.dp))
            }
        }
    }
}

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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(CoreR.string.back), tint = onSurface)
            }
            Text(
                stringResource(R.string.watch_link),
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
                    if (link.connected) stringResource(CoreR.string.connected) else stringResource(CoreR.string.not_connected),
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
                    Text(stringResource(R.string.mirror_to_watch), color = onSurface)
                    Text(stringResource(R.string.mirror_to_watch_desc), color = secondary, fontSize = 12.sp)
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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(CoreR.string.back), tint = onSurface)
            }
            Text(
                stringResource(CoreR.string.favourites),
                color = onSurface,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (viewModel.favouritesList.isEmpty()) {
            Text(
                stringResource(R.string.no_favourites_yet),
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
                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.remove), tint = secondary)
                }
            }
        }
    }
}
