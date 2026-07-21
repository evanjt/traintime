package com.evanjt.traintime.domain

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

// The per-app language override only reaches activity contexts on pre-33
// devices, so anything rendering text outside an activity (Glance widget,
// notifications, foreground services) wraps its context here with the tag
// stored in AppPrefs.appLanguage. An empty tag means follow the system.
object LocaleUtil {

    fun localised(context: Context, languageTag: String): Context {
        if (languageTag.isEmpty()) return context
        val locale = Locale.forLanguageTag(languageTag)
        val config = Configuration(context.resources.configuration)
        config.setLocale(locale)
        return context.createConfigurationContext(config)
    }
}
