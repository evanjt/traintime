package com.evanjt.traintime.data.api

import android.content.Context
import com.evanjt.traintime.data.prefs.AppPrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// The optional self-hosted API origin. "" means the built-in
// api.traintime.ch. Stored normalised so the same host never appears in two
// spellings and so the watch and phone compare equal after a sync.
object ApiHost {
    const val DEFAULT = "https://api.traintime.ch"

    // Trimmed input → "" (use the default), a normalised https origin, or
    // null when it isn't one. Anything but scheme, host and port is refused so
    // a path or query can't silently break the request URLs.
    fun normalise(input: String): String? {
        val trimmed = input.trim().trimEnd('/')
        if (trimmed.isEmpty()) return ""
        val url = trimmed.toHttpUrlOrNull() ?: return null
        if (url.scheme != "https" || url.host.isEmpty()) return null
        if (url.encodedPath != "/" || url.query != null || url.fragment != null) return null
        if (url.username.isNotEmpty() || url.password.isNotEmpty()) return null
        return trimmed
    }

    fun effective(override: String): String = override.ifEmpty { DEFAULT }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Call once per process from Application.onCreate. Keeps TrainApi.shared on
    // the saved host, including in the widget and service processes that
    // never build a ViewModel.
    fun bind(context: Context) {
        val prefs = AppPrefs(context)
        scope.launch { prefs.apiHost.collect { TrainApi.hostOverride = it } }
    }
}
