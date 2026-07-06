package com.evanjt.traintime.data.sbb

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

// Resolves a shared SBB link into a route. Short links return a splash page
// (plain 200, no redirect) whose HTML embeds the blob in two anchors, one
// GET plus a regex, no cookies or JS. This talks to a.sbbmobile.ch, not
// api.traintime.ch, so no API key is sent.
class SbbShareService(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build(),
) {
    @Throws(IOException::class, SbbDecodeException::class)
    suspend fun resolve(link: SbbShareLink): SharedRoute = when (link) {
        is SbbShareLink.Blob -> SbbTripDecoder.decode(link.blob)
        is SbbShareLink.Short -> {
            val html = fetch(link.url)
            val blob = SbbTripDecoder.extractBlobFromHtml(html)
                ?: throw SbbDecodeException(SbbDecodeException.Reason.MALFORMED)
            SbbTripDecoder.decode(blob)
        }
    }

    private suspend fun fetch(url: String): String = withContext(Dispatchers.IO) {
        val response = client.newCall(Request.Builder().url(url).build()).execute()
        response.use {
            if (it.code != 200) throw IOException("HTTP ${it.code}")
            it.body?.string() ?: throw IOException("Empty body")
        }
    }

    companion object {
        val shared = SbbShareService()
    }
}
