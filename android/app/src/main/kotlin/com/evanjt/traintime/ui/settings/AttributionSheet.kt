package com.evanjt.traintime.ui.settings

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Credits for the data and software TrainTime builds on. Two sources require attribution (Open
// Transport Data Switzerland, the Garmin SDK); the rest is credited as good practice. Peer of
// SettingsSheet.kt, opened from its "Attribution" row. The open-source list is Android's real
// shipping stack — the iOS screen lists only the Garmin SDK.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttributionSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    fun open(url: String) = runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                "Attribution",
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 4.dp).align(Alignment.CenterHorizontally),
            )
            Text(
                "The data and software TrainTime is built on.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                modifier = Modifier.padding(bottom = 8.dp).align(Alignment.CenterHorizontally),
            )

            SectionHeader("Departure data")
            Paragraph(
                "Live departures from Open Transport Data Switzerland, operated by Swiss " +
                    "Federal Railways (SBB), via the OJP API.",
            )
            LinkEntry("Terms of use", "opentransportdata.swiss") {
                open("https://opentransportdata.swiss/en/terms-of-use/")
            }

            Divider()
            SectionHeader("Map")
            Paragraph("Swiss border outline from Natural Earth, 1:10m resolution, public domain.")
            LinkEntry("Natural Earth", "naturalearthdata.com") {
                open("https://www.naturalearthdata.com")
            }

            Divider()
            SectionHeader("Open source and third party")
            Entry("Jetpack Compose, AndroidX, Glance, Wear Compose", "Apache License 2.0")
            Entry("OkHttp", "Apache License 2.0")
            Entry("Kotlin, kotlinx", "Coroutines and serialisation. Apache License 2.0")
            Entry("Google Play Services", "Location, wearable, in-app review. Google terms")
            LinkEntry("Garmin Connect IQ Mobile SDK", "© Garmin. Used under its SDK licence.") {
                open("https://developer.garmin.com/connect-iq/")
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title.uppercase(),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.8.sp,
        modifier = Modifier.padding(top = 20.dp, bottom = 10.dp),
    )
}

@Composable
private fun Paragraph(text: String) {
    Text(
        text,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        modifier = Modifier.padding(bottom = 4.dp),
    )
}

// A named credit: title over a muted licence/detail line.
@Composable
private fun Entry(name: String, detail: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(name, color = MaterialTheme.colorScheme.onSurface, fontSize = 15.sp)
        Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
    }
}

// Same as Entry but the whole row opens a link, with a trailing external-link glyph.
@Composable
private fun LinkEntry(name: String, detail: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(vertical = 8.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(name, color = MaterialTheme.colorScheme.onSurface, fontSize = 15.sp)
            Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        }
        Icon(
            Icons.Filled.OpenInNew,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun Divider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f),
        modifier = Modifier.padding(top = 20.dp),
    )
}
