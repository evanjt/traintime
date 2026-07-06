package com.evanjt.traintime.data.sbb

import com.evanjt.traintime.data.model.Departure
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Base64
import java.util.zip.Inflater
import kotlin.math.abs

// An SBB Mobile trip link found in shared text. Three shapes carry the same
// payload: the a.sbbmobile.ch short link (resolved via its splash page), the
// sbbmobile:// app link, and the www.sbb.ch web link.
sealed interface SbbShareLink {
    data class Short(val url: String) : SbbShareLink
    data class Blob(val blob: String) : SbbShareLink

    companion object {
        private val SHORT = Regex("""https?://a\.sbbmobile\.ch/s/[A-Za-z0-9]+""")
        private val RECON = Regex("""sbbmobile://trip\?recon=([A-Za-z0-9_.\-]+)""")
        private val TRIP_ID = Regex("""https?://[^\s"']*sbb\.ch/[^\s"']*trip\?tripId=([A-Za-z0-9_.\-]+)""")

        fun findIn(text: String): SbbShareLink? {
            SHORT.find(text)?.let { return Short(it.value) }
            RECON.find(text)?.let { return Blob(it.groupValues[1]) }
            TRIP_ID.find(text)?.let { return Blob(it.groupValues[1]) }
            return null
        }
    }
}

class SbbDecodeException(val reason: Reason, cause: Throwable? = null) :
    Exception("SBB trip decode failed: $reason", cause) {
    enum class Reason { UNSUPPORTED_VERSION, MALFORMED, NO_RIDE_LEGS }
}

// Decodes the SBB Mobile trip blob: `3HA.<recon>.<query>`, each segment
// base64url + zlib deflate. The recon segment is a HAFAS reconstruction
// context: `¶`-separated sections, the HKI section holds `§`-separated legs
// with `$`-separated fields and `@`-separated k=v locations. Times are
// Swiss-local `yyyyMMddHHmm`. Proprietary and undocumented, hence the
// version guard and the blanket MALFORMED catch.
object SbbTripDecoder {
    const val SUPPORTED_VERSION = "3HA"

    private val SPLASH_RECON = Regex("""sbbmobile://trip\?recon=([A-Za-z0-9_.\-]+)""")
    private val SPLASH_TRIP_ID = Regex("""sbb\.ch/[^\s"']*trip\?tripId=([A-Za-z0-9_.\-]+)""")
    private val TIME_FORMAT = DateTimeFormatter.ofPattern("yyyyMMddHHmm")

    fun extractBlobFromHtml(html: String): String? =
        SPLASH_RECON.find(html)?.groupValues?.get(1)
            ?: SPLASH_TRIP_ID.find(html)?.groupValues?.get(1)

    @Throws(SbbDecodeException::class)
    fun decode(blob: String, zone: ZoneId = ZoneId.of("Europe/Zurich")): SharedRoute {
        val parts = blob.split(".")
        if (parts.size < 2) throw SbbDecodeException(SbbDecodeException.Reason.MALFORMED)
        if (parts[0] != SUPPORTED_VERSION) {
            throw SbbDecodeException(SbbDecodeException.Reason.UNSUPPORTED_VERSION)
        }
        val legs = try {
            val recon = inflate(parts[1])
            parseLegs(section(recon, "HKI"), zone)
        } catch (e: SbbDecodeException) {
            throw e
        } catch (e: Exception) {
            throw SbbDecodeException(SbbDecodeException.Reason.MALFORMED, e)
        }
        if (legs.none { it.type == LegType.RIDE }) {
            throw SbbDecodeException(SbbDecodeException.Reason.NO_RIDE_LEGS)
        }
        return SharedRoute(legs = legs, sourceBlob = blob)
    }

    private fun inflate(segment: String): String {
        val raw = Base64.getUrlDecoder().decode(segment.trimEnd('='))
        val inflater = Inflater()
        inflater.setInput(raw)
        val buffer = ByteArray(8 * 1024)
        val bytes = java.io.ByteArrayOutputStream()
        while (!inflater.finished()) {
            val n = inflater.inflate(buffer)
            if (n == 0 && inflater.needsInput()) break
            bytes.write(buffer, 0, n)
        }
        inflater.end()
        return bytes.toString(Charsets.UTF_8.name())
    }

    // Sections come as ¶NAME¶value¶NAME¶value…
    private fun section(recon: String, name: String): String {
        val parts = recon.split("¶")
        for (i in 1 until parts.size - 1 step 2) {
            if (parts[i] == name) return parts[i + 1]
        }
        throw SbbDecodeException(SbbDecodeException.Reason.MALFORMED)
    }

    private fun parseLegs(hki: String, zone: ZoneId): List<RouteLeg> =
        hki.split("§").map { raw -> parseLeg(raw, zone) }

    // Leg shape: <kind>$<fromLoc>$<toLoc>$<dep>$<arr>$<line>$… where kind is
    // T (ride), W (walk) or G@F (footpath with raw coordinates).
    private fun parseLeg(raw: String, zone: ZoneId): RouteLeg {
        val kind = raw.first()
        val body = raw.substringAfter('$')
        val fields = body.split("$")
        val from = parseLocation(fields[0])
        val to = parseLocation(fields[1])
        val line = fields.getOrNull(4)?.trim().orEmpty()
        val lineParts = line.split(Regex("""\s+""")).filter { it.isNotEmpty() }
        val ride = kind == 'T' && line.isNotEmpty()
        return RouteLeg(
            type = if (kind == 'T') LegType.RIDE else LegType.WALK,
            originId = from.id,
            originName = from.name,
            originLat = from.lat,
            originLon = from.lon,
            destId = to.id,
            destName = to.name,
            destLat = to.lat,
            destLon = to.lon,
            depTs = parseTime(fields[2], zone),
            arrTs = parseTime(fields[3], zone),
            category = if (ride) lineParts.getOrNull(0) else null,
            lineNumber = if (ride) lineParts.getOrNull(1) else null,
            trainNumber = if (ride) lineParts.getOrNull(2) else null,
        )
    }

    private data class Location(val name: String, val id: String?, val lat: Double?, val lon: Double?)

    // A=1@O=Sion@X=7359199@Y=46227549@L=8501506@a=128@
    private fun parseLocation(token: String): Location {
        val fields = token.split("@")
            .filter { it.contains("=") }
            .associate { it.substringBefore("=") to it.substringAfter("=") }
        return Location(
            name = fields["O"] ?: "",
            id = fields["L"],
            lat = fields["Y"]?.toLongOrNull()?.let { it / 1e6 },
            lon = fields["X"]?.toLongOrNull()?.let { it / 1e6 },
        )
    }

    private fun parseTime(value: String, zone: ZoneId): Long =
        LocalDateTime.parse(value, TIME_FORMAT).atZone(zone).toEpochSecond()
}

// Finds the shared leg on a live departure board. Primary key is the exact
// train (journey number + scheduled time); fallback tolerates a missing
// trainNumber by normalising the line ("IR" + "90" vs Departure's "IR90").
// Never matches on destination: the leg's destName is where the user alights,
// Departure.destination is the train's terminus.
fun matchDeparture(departures: List<Departure>, leg: RouteLeg): Departure? {
    if (leg.type != LegType.RIDE) return null
    departures.firstOrNull {
        leg.trainNumber != null &&
            it.trainNumber == leg.trainNumber &&
            it.departureTimestamp == leg.depTs
    }?.let { return it }
    val legLine = ((leg.category ?: "") + (leg.lineNumber ?: "")).lowercase()
    return departures.firstOrNull {
        val ts = it.departureTimestamp ?: return@firstOrNull false
        abs(ts - leg.depTs) <= 60 &&
            legLine.isNotEmpty() &&
            (it.lineNumber.lowercase() == legLine || it.lineNumber.lowercase() == leg.lineNumber?.lowercase())
    }
}
