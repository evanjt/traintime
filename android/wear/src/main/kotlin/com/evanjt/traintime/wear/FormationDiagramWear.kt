package com.evanjt.traintime.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon

private data class FormationColors(
    val body: Color,
    val outline: Color,
    val groupBorder: Color,
    val connector: Color,
    val sectorLine: Color,
    val carNumber: Color,
    val featureIcon: Color,
    val primary: Color,
    val labelBackground: Color,
    val accentBand: Color,
)

@Composable
private fun formationColors(): FormationColors {
    val dark = isSystemInDarkTheme()
    val primary = MaterialTheme.colors.onBackground
    return if (dark) {
        FormationColors(
            body = Color(0xFF2E2E2E),
            outline = Color(0xFF4D4D4D),
            groupBorder = Color(0xFF474747),
            connector = Color(0xFF1F1F1F),
            sectorLine = Color(0xFF595959),
            carNumber = Color(0xFFA6A6A6),
            featureIcon = Color(0xFF9C9C9C),
            primary = primary,
            labelBackground = MaterialTheme.colors.background,
            accentBand = primary.copy(alpha = 0.08f),
        )
    } else {
        FormationColors(
            body = Color(0xFFE5E5EA),
            outline = Color(0xFFC7C7CC),
            groupBorder = Color(0xFFC7C7CC),
            connector = Color(0xFFD1D1D6),
            sectorLine = Color(0xFFC7C7CC),
            carNumber = Color(0xFF6D6D72),
            featureIcon = Color(0xFF8E8E93),
            primary = primary,
            labelBackground = MaterialTheme.colors.background,
            accentBand = primary.copy(alpha = 0.06f),
        )
    }
}

private data class WagonGroup(val sector: String, val wagons: List<FormationWagon>)

private fun sectorGroups(wagons: List<FormationWagon>): List<WagonGroup> {
    val groups = mutableListOf<WagonGroup>()
    var current = ""
    var batch = mutableListOf<FormationWagon>()
    for (w in wagons) {
        if (w.sector != current) {
            if (batch.isNotEmpty()) groups.add(WagonGroup(current, batch))
            current = w.sector
            batch = mutableListOf(w)
        } else {
            batch.add(w)
        }
    }
    if (batch.isNotEmpty()) groups.add(WagonGroup(current, batch))
    return groups
}

// Single-letter glyphs instead of material icons to keep the watch APK lean.
private fun featureGlyph(feature: String): String = when (feature) {
    "wheelchair" -> "♿" // ♿
    "restaurant" -> "🍴" // 🍴
    "family" -> "F"
    "business" -> "B"
    "low_floor" -> "↓" // ↓
    else -> "?"
}

// Port of the phone FormationDiagram: locomotive + carriages grouped by sector,
// 1st-class stripe, feature glyph, sector bracket labels.
@Composable
fun FormationDiagramWear(formation: Formation, modifier: Modifier = Modifier) {
    val carriageHeight = 26.dp
    val gap = 2.dp
    val locoWidth = 26.dp
    val colors = formationColors()

    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
        val n = formation.wagons.size.coerceAtLeast(1)
        val available = maxWidth - locoWidth - gap * (n - 1)
        val carriageWidth = (available / n).coerceIn(16.dp, 44.dp)
        val groups = sectorGroups(formation.wagons)

        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Loco(width = locoWidth, height = carriageHeight, colors = colors)
                groups.forEachIndexed { gi, group ->
                    if (gi > 0) Connector(gap, carriageHeight, colors)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .padding(vertical = 2.dp)
                            .border(0.5.dp, colors.groupBorder, RoundedCornerShape(5.dp)),
                    ) {
                        group.wagons.forEachIndexed { wi, wagon ->
                            if (wi > 0) Connector(gap, carriageHeight, colors)
                            Carriage(
                                wagon = wagon,
                                width = carriageWidth,
                                height = carriageHeight,
                                showFeature = carriageWidth >= 26.dp,
                                colors = colors,
                            )
                        }
                    }
                }
            }

            if (formation.sectors.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(locoWidth), contentAlignment = Alignment.Center) {
                        Text("◀", color = colors.primary, fontSize = 10.sp) // ◀ direction of travel
                    }
                    groups.forEachIndexed { i, group ->
                        val groupWidth =
                            carriageWidth * group.wagons.size +
                                gap * (group.wagons.size - 1).coerceAtLeast(0) +
                                if (i > 0) gap else 0.dp
                        Box(Modifier.width(groupWidth).height(14.dp), contentAlignment = Alignment.Center) {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 2.dp)
                                    .height(0.5.dp)
                                    .background(colors.sectorLine),
                            )
                            Text(
                                group.sector,
                                color = colors.primary,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.background(colors.labelBackground).padding(horizontal = 3.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Connector(gap: Dp, carriageHeight: Dp, colors: FormationColors) {
    Box(Modifier.width(gap).height(carriageHeight * 0.35f).background(colors.connector))
}

@Composable
private fun Loco(width: Dp, height: Dp, colors: FormationColors) {
    Box(
        Modifier
            .size(width, height)
            .clip(RoundedCornerShape(topStart = height * 0.6f, topEnd = 3.dp, bottomEnd = 3.dp, bottomStart = 3.dp))
            .background(colors.body),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(7.dp, height * 0.38f)
                .offset(x = (-2).dp, y = (-2).dp)
                .background(colors.accentBand, RoundedCornerShape(2.dp)),
        )
    }
}

@Composable
private fun Carriage(wagon: FormationWagon, width: Dp, height: Dp, showFeature: Boolean, colors: FormationColors) {
    Box(
        Modifier
            .size(width, height)
            .alpha(if (wagon.closed) 0.4f else 1f)
            .clip(RoundedCornerShape(3.dp))
            .background(colors.body)
            .border(0.5.dp, colors.outline, RoundedCornerShape(3.dp)),
        contentAlignment = Alignment.Center,
    ) {
        if (wagon.wagonClass == 1) {
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 1.5.dp)
                    .width(width - 4.dp)
                    .height(2.5.dp)
                    .background(Color(0xFFEBB800), RoundedCornerShape(1.dp)),
            )
        }
        Text("${wagon.number}", color = colors.carNumber, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
        if (showFeature) {
            wagon.features.firstOrNull()?.let { feature ->
                Text(
                    featureGlyph(feature),
                    color = colors.featureIcon,
                    fontSize = 8.sp,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(end = 2.dp, bottom = 1.dp),
                )
            }
        }
    }
}
