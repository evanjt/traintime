package com.evanjt.traintime.domain

// One-time "TrainTime runs on your Garmin too" tip on the phone. Pure so the
// gates can be unit-tested without the Connect IQ SDK. Garmin Connect must be
// on the phone, no Garmin must ever have linked, and the tip must be unseen.
// It waits until the tour is done and the app has been launched a few times,
// so it never arrives with the tour, which already points at the Garmin app.
object GarminTipGate {
    const val MIN_LAUNCHES = 2

    fun shouldShow(
        garminConnectInstalled: Boolean,
        everLinked: Boolean,
        seen: Boolean,
        tourDone: Boolean,
        launches: Int,
    ): Boolean = garminConnectInstalled && !everLinked && !seen && tourDone &&
        launches >= MIN_LAUNCHES
}

// The Connect IQ Store page in the app's language. Swiss locales redirect to
// these on the store anyway, and anything else falls back to English.
object ConnectIqStore {
    const val APP_ID = "c70bbfae-846a-4d00-9e96-d485217035fb"

    fun url(language: String): String {
        val locale = when (language.lowercase().substringBefore('-')) {
            "de" -> "de-DE"
            "fr" -> "fr-FR"
            "it" -> "it-IT"
            else -> "en-US"
        }
        return "https://apps.garmin.com/$locale/apps/$APP_ID"
    }
}
