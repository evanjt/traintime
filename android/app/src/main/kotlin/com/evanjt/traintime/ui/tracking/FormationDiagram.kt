package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Accessible
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Work
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon

// Adaptive carriage greys, dark values match the original watch look, light
// values track Apple's systemGray scale.
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
    val primary = MaterialTheme.colorScheme.onBackground
    return if (dark) {
        FormationColors(
            body = Color(0xFF2E2E2E),
            outline = Color(0xFF4D4D4D),
            groupBorder = Color(0xFF474747),
            connector = Color(0xFF1F1F1F),
            sectorLine = Color(0xFF595959),
            carNumber = Color(0xFFA6A6A6),
            featureIcon = Color(0xFF737373),
            primary = primary,
            labelBackground = MaterialTheme.colorScheme.background,
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
            labelBackground = MaterialTheme.colorScheme.background,
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

private fun featureIcon(feature: String): ImageVector = when (feature) {
    "wheelchair" -> Icons.Filled.Accessible
    "restaurant" -> Icons.Filled.Restaurant
    "family" -> Icons.Filled.FamilyRestroom
    "business" -> Icons.Filled.Work
    "low_floor" -> Icons.Filled.ArrowDownward
    else -> Icons.Filled.QuestionMark
}

// Port of FormationDiagramView.swift: locomotive + carriages grouped by
// sector, 1st-class stripe, feature icons, sector bracket labels.
@Composable
fun FormationDiagram(formation: Formation, modifier: Modifier = Modifier) {
    val carriageHeight = 30.dp
    val gap = 2.dp
    val locoWidth = 32.dp
    val colors = formationColors()

    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
        val n = formation.wagons.size
        val available = maxWidth - locoWidth - gap * (n - 1)
        val carriageWidth = (available / n).coerceIn(20.dp, 56.dp)
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
                                showFeature = carriageWidth >= 30.dp,
                                colors = colors,
                            )
                        }
                    }
                }
            }

            // Sector labels with bracket lines
            if (formation.sectors.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(locoWidth), contentAlignment = Alignment.Center) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.direction_of_travel_cd),
                            tint = colors.primary,
                            modifier = Modifier.size(12.dp),
                        )
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
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier
                                    .background(colors.labelBackground)
                                    .padding(horizontal = 3.dp),
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
    Box(
        Modifier
            .width(gap)
            .height(carriageHeight * 0.35f)
            .background(colors.connector),
    )
}

@Composable
private fun Loco(width: Dp, height: Dp, colors: FormationColors) {
    // Simplified nose: rounded body with a steeper leading corner.
    Box(
        Modifier
            .size(width, height)
            .clip(RoundedCornerShape(topStart = height * 0.6f, topEnd = 3.dp, bottomEnd = 3.dp, bottomStart = 3.dp))
            .background(colors.body),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(8.dp, height * 0.38f)
                .offset(x = (-2).dp, y = (-3).dp)
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
        // 1st class accent: yellow stripe along the top
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

        // Window band
        Box(
            Modifier
                .offset(y = (-3).dp)
                .width(width - 6.dp)
                .height(6.dp)
                .background(colors.accentBand, RoundedCornerShape(1.dp)),
        )

        Text(
            "${wagon.number}",
            color = colors.carNumber,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.offset(y = 2.dp),
        )

        if (showFeature) {
            wagon.features.firstOrNull()?.let { feature ->
                Icon(
                    featureIcon(feature),
                    contentDescription = feature,
                    tint = colors.featureIcon,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 2.dp, bottom = 2.dp)
                        .size(7.dp),
                )
            }
        }

        if (wagon.closed) {
            Box(
                Modifier
                    .width(width * 0.7f)
                    .height(1.dp)
                    .background(colors.primary.copy(alpha = 0.35f)),
            )
        }
    }
}
