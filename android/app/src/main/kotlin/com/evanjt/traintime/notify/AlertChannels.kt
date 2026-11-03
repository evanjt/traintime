package com.evanjt.traintime.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import com.evanjt.traintime.R
import com.evanjt.traintime.data.prefs.AppPrefs
import com.evanjt.traintime.domain.LocaleUtil
import kotlinx.coroutines.flow.first

// The channels every sounding alert posts on. Once a channel exists only the
// user can change its sound, so "Alert sounds" off can't edit the originals:
// each gets a twin with no sound that still pops up and vibrates, and the
// picker chooses one at send time. Nothing is deleted, so the user's own
// channel settings survive and no "deleted categories" count appears.
object AlertChannels {
    const val TRACKING = "tracking_alerts"
    const val TRACKING_QUIET = "tracking_alerts_quiet"
    const val REMINDER = "pending_route"
    const val REMINDER_QUIET = "pending_route_quiet"

    // A plain double buzz, close to the system default the originals use.
    private val QUIET_VIBRATION = longArrayOf(0, 250, 150, 250)

    private class Spec(val id: String, val nameRes: Int, val quiet: Boolean)

    private val SPECS = listOf(
        Spec(TRACKING, R.string.tracking_alert_channel, quiet = false),
        Spec(TRACKING_QUIET, R.string.tracking_alert_channel_silent, quiet = true),
        Spec(REMINDER, R.string.channel_saved_routes, quiet = false),
        Spec(REMINDER_QUIET, R.string.channel_saved_routes_silent, quiet = true),
    )

    fun forAlert(sounds: Boolean): String = if (sounds) TRACKING else TRACKING_QUIET

    fun forReminder(sounds: Boolean): String = if (sounds) REMINDER else REMINDER_QUIET

    suspend fun forAlert(context: Context): String = forAlert(AppPrefs(context).alertSounds.first())

    suspend fun forReminder(context: Context): String = forReminder(AppPrefs(context).alertSounds.first())

    suspend fun ensure(context: Context) {
        create(context, LocaleUtil.localised(context, AppPrefs(context).appLanguage.first()))
    }

    // Creating an existing channel only refreshes its name, so this is safe on
    // every post and keeps the names in the chosen language. `names` is a
    // context already wrapped in that language.
    fun create(context: Context, names: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        for (spec in SPECS) {
            manager.createNotificationChannel(
                NotificationChannel(spec.id, names.getString(spec.nameRes), NotificationManager.IMPORTANCE_HIGH).apply {
                    if (spec.quiet) {
                        setSound(null, null)
                        enableVibration(true)
                        vibrationPattern = QUIET_VIBRATION
                    }
                },
            )
        }
    }
}
