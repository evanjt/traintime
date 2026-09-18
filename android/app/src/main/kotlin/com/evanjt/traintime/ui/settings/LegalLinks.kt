package com.evanjt.traintime.ui.settings

// The website's legal pages. The terms page exists in the four app languages, the privacy page in
// English only, and the FOT dataset page on opendata.swiss follows the same language codes.
object LegalLinks {
    const val PRIVACY = "https://traintime.ch/privacy"

    private val translated = setOf("de", "fr", "it")

    fun terms(language: String): String =
        if (language in translated) "https://traintime.ch/terms/$language/" else "https://traintime.ch/terms/"

    fun stationsDataset(language: String): String {
        val code = if (language in translated) language else "en"
        return "https://opendata.swiss/$code/dataset/haltestellen-des-offentlichen-verkehrs"
    }
}
