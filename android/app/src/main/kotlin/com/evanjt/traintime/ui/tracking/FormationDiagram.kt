package com.evanjt.traintime.ui.tracking

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.PedalBike
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evanjt.traintime.LocalAppPalette
import com.evanjt.traintime.R
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon

// Adaptive carriage greys, dark values match the original watch look, light
// values track Apple's systemGray scale.
private data class FormationColors(
    val body: Color,
    val outline: Color,
    val unitBorder: Color,
    val connector: Color,
    val sectorLine: Color,
    val carNumber: Color,
    val muted: Color,
    val primary: Color,
    val labelBackground: Color,
    val accentBand: Color,
    val noPassage: Color,
)

// Follows the app theme rather than the system one, so a forced light or dark
// mode draws the matching greys.
@Composable
private fun formationColors(): FormationColors {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val primary = MaterialTheme.colorScheme.onBackground
    val noPassage = LocalAppPalette.current.darkRed
    return if (dark) {
        FormationColors(
            body = Color(0xFF2E2E2E),
            outline = Color(0xFF4D4D4D),
            unitBorder = Color(0xFF5C5C5C),
            connector = Color(0xFF1F1F1F),
            sectorLine = Color(0xFF595959),
            carNumber = Color(0xFFC7C7C7),
            muted = Color(0xFF8E8E8E),
            primary = primary,
            labelBackground = MaterialTheme.colorScheme.background,
            accentBand = primary.copy(alpha = 0.08f),
            noPassage = noPassage,
        )
    } else {
        FormationColors(
            body = Color(0xFFE5E5EA),
            outline = Color(0xFFC7C7CC),
            unitBorder = Color(0xFFAEAEB2),
            connector = Color(0xFFD1D1D6),
            sectorLine = Color(0xFFC7C7CC),
            carNumber = Color(0xFF48484A),
            muted = Color(0xFF8E8E93),
            primary = primary,
            labelBackground = MaterialTheme.colorScheme.background,
            accentBand = primary.copy(alpha = 0.06f),
            noPassage = noPassage,
        )
    }
}

internal object FormationMetrics {
    const val NOSE = 28f
    const val NOSE_GAP = 4f
    const val GAP = 2f
    // Wide enough for the 3 dp bar with clear space either side of it.
    const val BREAK_GAP = 9f
    const val BAR_WIDTH = 3f
    const val END_PAD = 2f
    const val MAX_CAR = 56f
}

// Car positions in dp from the left edge, the nose first. Cars shrink to fit
// the width with no floor, so a long train never runs off the screen.
internal data class FormationLayout(val carWidth: Float, val carLefts: List<Float>, val barCentres: List<Float>) {
    val width: Float
        get() = (carLefts.lastOrNull()?.plus(carWidth) ?: FormationMetrics.NOSE) + FormationMetrics.END_PAD
}

internal fun formationLayout(wagons: List<FormationWagon>, width: Float): FormationLayout {
    val m = FormationMetrics
    val n = wagons.size
    if (n == 0) return FormationLayout(0f, emptyList(), emptyList())
    val gaps = (0 until n - 1).sumOf { (if (wagons[it].noPassageAfter) m.BREAK_GAP else m.GAP).toDouble() }.toFloat()
    val available = width - m.NOSE - m.NOSE_GAP - m.END_PAD - gaps
    val carWidth = (available / n).coerceIn(0f, m.MAX_CAR)
    val lefts = mutableListOf<Float>()
    val bars = mutableListOf<Float>()
    var x = m.NOSE + m.NOSE_GAP
    wagons.forEachIndexed { i, w ->
        lefts.add(x)
        x += carWidth
        if (i < n - 1) {
            if (w.noPassageAfter) {
                bars.add(x + m.BREAK_GAP / 2)
                x += m.BREAK_GAP
            } else {
                x += m.GAP
            }
        }
    }
    return FormationLayout(carWidth, lefts, bars)
}

// The one amenity a car shows in the icon lane, by priority. Low floor and
// pram space are left out, and an unknown feature draws nothing.
internal val laneFeatures = listOf("restaurant", "wheelchair", "family", "bike", "business")

internal fun laneFeature(wagon: FormationWagon): String? =
    if (wagon.closed) null else laneFeatures.firstOrNull { it in wagon.features }

private fun laneIcon(feature: String): Pair<ImageVector, Int> = when (feature) {
    "restaurant" -> Icons.Filled.Restaurant to R.string.formation_restaurant_cd
    "wheelchair" -> Icons.Filled.Accessible to R.string.formation_wheelchair_cd
    "family" -> Icons.Filled.FamilyRestroom to R.string.formation_family_cd
    "bike" -> Icons.Filled.PedalBike to R.string.formation_bike_cd
    else -> Icons.Filled.Work to R.string.formation_business_cd
}

// Runs of cars between two no-passage bars, each drawn with its own outline.
private fun units(wagons: List<FormationWagon>): List<IntRange> {
    val out = mutableListOf<IntRange>()
    var start = 0
    wagons.forEachIndexed { i, w ->
        if (w.noPassageAfter || i == wagons.lastIndex) {
            out.add(start..i)
            start = i + 1
        }
    }
    return out
}

private fun sectorRuns(wagons: List<FormationWagon>): List<Pair<String, IntRange>> {
    val out = mutableListOf<Pair<String, IntRange>>()
    var start = 0
    for (i in 1..wagons.size) {
        if (i == wagons.size || wagons[i].sector != wagons[start].sector) {
            out.add(wagons[start].sector to (start until i))
            start = i
        }
    }
    return out
}

private const val LANE_HEIGHT = 16f
private const val CAR_HEIGHT = 30f
// The bar stands this far proud of the cars above and below.
private const val BAR_PROUD = 3f

// Nose and direction arrow on the left at the first car, an icon lane above
// the cars, red bars where there is no passage, sector letters below.
@Composable
fun FormationDiagram(formation: Formation, modifier: Modifier = Modifier) {
    val colors = formationColors()
    val wagons = formation.wagons

    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
        val layout = formationLayout(wagons, maxWidth.value)
        val carWidth = layout.carWidth

        Column {
            Box(Modifier.width(layout.width.dp).height(LANE_HEIGHT.dp)) {
                val iconSize = minOf(12f, carWidth - 2f).coerceAtLeast(0f)
                wagons.forEachIndexed { i, w ->
                    val feature = laneFeature(w) ?: return@forEachIndexed
                    val (icon, label) = laneIcon(feature)
                    Icon(
                        icon,
                        contentDescription = stringResource(label),
                        tint = if (feature == "bike") colors.muted else colors.primary,
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .offset(x = (layout.carLefts[i] + (carWidth - iconSize) / 2).dp, y = (-2).dp)
                            .size(iconSize.dp),
                    )
                }
            }

            Box(Modifier.width(layout.width.dp).height((CAR_HEIGHT + BAR_PROUD * 2).dp)) {
                Nose(
                    width = FormationMetrics.NOSE.dp,
                    height = CAR_HEIGHT.dp,
                    colors = colors,
                    modifier = Modifier.offset(y = BAR_PROUD.dp),
                )
                for (unit in units(wagons)) {
                    val left = layout.carLefts[unit.first] - 1.5f
                    val right = layout.carLefts[unit.last] + carWidth + 1.5f
                    Box(
                        Modifier
                            .offset(x = left.dp, y = (BAR_PROUD - 1.5f).dp)
                            .size((right - left).dp, (CAR_HEIGHT + 3f).dp)
                            .border(0.5.dp, colors.unitBorder, RoundedCornerShape(5.dp)),
                    )
                    for (i in unit.first until unit.last) {
                        Box(
                            Modifier
                                .offset(
                                    x = (layout.carLefts[i] + carWidth).dp,
                                    y = (BAR_PROUD + CAR_HEIGHT * 0.325f).dp,
                                )
                                .size(FormationMetrics.GAP.dp, (CAR_HEIGHT * 0.35f).dp)
                                .background(colors.connector),
                        )
                    }
                }
                wagons.forEachIndexed { i, w ->
                    Carriage(
                        wagon = w,
                        width = carWidth.dp,
                        height = CAR_HEIGHT.dp,
                        colors = colors,
                        modifier = Modifier.offset(x = layout.carLefts[i].dp, y = BAR_PROUD.dp),
                    )
                }
                val barLabel = stringResource(R.string.formation_no_passage_cd)
                for (centre in layout.barCentres) {
                    Box(
                        Modifier
                            .offset(x = (centre - FormationMetrics.BAR_WIDTH / 2).dp)
                            .size(FormationMetrics.BAR_WIDTH.dp, (CAR_HEIGHT + BAR_PROUD * 2).dp)
                            .background(colors.noPassage, RoundedCornerShape(1.dp))
                            .semantics { contentDescription = barLabel },
                    )
                }
            }

            Box(Modifier.width(layout.width.dp).padding(top = 2.dp)) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.direction_of_travel_cd),
                    tint = colors.primary,
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .offset(x = ((FormationMetrics.NOSE - 12f) / 2).dp)
                        .size(12.dp),
                )
                if (formation.sectors.isNotEmpty()) {
                    for ((sector, run) in sectorRuns(wagons)) {
                        if (sector.isEmpty()) continue
                        val left = layout.carLefts[run.first]
                        val span = layout.carLefts[run.last] + carWidth - left
                        SectorLabel(
                            sector = sector,
                            colors = colors,
                            modifier = Modifier.offset(x = left.dp).width(span.dp),
                        )
                    }
                }
            }
        }
    }
}

// The letter sizes its own box, so it is never clipped however narrow the run.
@Composable
private fun SectorLabel(sector: String, colors: FormationColors, modifier: Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 1.dp)
                .height(0.5.dp)
                .background(colors.sectorLine),
        )
        Text(
            sector,
            color = colors.primary,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier
                .background(colors.labelBackground)
                .padding(horizontal = 2.dp),
        )
    }
}

@Composable
private fun Nose(width: Dp, height: Dp, colors: FormationColors, modifier: Modifier) {
    // Simplified nose: rounded body with a steeper leading corner.
    Box(
        modifier
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
private fun Carriage(wagon: FormationWagon, width: Dp, height: Dp, colors: FormationColors, modifier: Modifier) {
    Box(
        modifier
            .size(width, height)
            .alpha(if (wagon.closed) 0.35f else 1f)
            .clip(RoundedCornerShape(3.dp))
            .background(colors.body)
            .border(0.5.dp, colors.outline, RoundedCornerShape(3.dp)),
        contentAlignment = Alignment.Center,
    ) {
        // First class: yellow roof stripe, half width on a mixed-class car.
        if (wagon.wagonClass == 1) {
            val stripe = width - 4.dp
            Box(
                Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 2.dp, top = 1.5.dp)
                    .width(if (wagon.mixedClass) stripe / 2 else stripe)
                    .height(2.5.dp)
                    .background(Color(0xFFEBB800), RoundedCornerShape(1.dp)),
            )
        }

        if (!wagon.closed) {
            Text(
                "${wagon.number}",
                color = colors.carNumber,
                fontSize = when {
                    width >= 22.dp -> 11.sp
                    width >= 17.dp -> 10.sp
                    else -> 9.sp
                },
                letterSpacing = if (width >= 17.dp) 0.sp else (-0.3).sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.offset(y = 1.dp),
            )
        }
    }
}
