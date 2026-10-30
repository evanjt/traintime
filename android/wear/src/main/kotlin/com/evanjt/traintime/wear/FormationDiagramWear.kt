package com.evanjt.traintime.wear

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Accessible
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.PedalBike
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import kotlinx.coroutines.delay

// The watch always draws the dark palette: the face is black whatever the system theme
private val bodyColour = Color(0xFF555555)
private val firstClassColour = Color(0xFFFFFF00)
private val breakColour = Color(0xFFFF0000)
private val tickColour = Color(0xFFAAAAAA)
private val sectorColour = Color(0xFFAAAAAA)

private const val CAR_TOP = 3f
private const val CAR_HEIGHT = 16f
private const val LINE_TOP = CAR_TOP + CAR_HEIGHT + 2f
private const val LINE_HEIGHT = 3f
private const val TICK_TOP = LINE_TOP + LINE_HEIGHT + 1f
private const val SECTOR_TOP = TICK_TOP + 3f
private const val STRIP_HEIGHT = SECTOR_TOP + 12f

private val labelStyle = TextStyle(color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.SemiBold)
private val sectorStyle = TextStyle(color = sectorColour, fontSize = 9.sp, fontWeight = FontWeight.SemiBold)

private fun Amenity.icon(): ImageVector = when (this) {
    Amenity.RESTAURANT -> Icons.Filled.Restaurant
    Amenity.WHEELCHAIR -> Icons.Filled.Accessible
    Amenity.FAMILY -> Icons.Filled.FamilyRestroom
    Amenity.BIKE -> Icons.Filled.PedalBike
}

@Composable
private fun Amenity.label(): String = stringResource(
    when (this) {
        Amenity.RESTAURANT -> R.string.formation_restaurant
        Amenity.WHEELCHAIR -> R.string.formation_wheelchair
        Amenity.FAMILY -> R.string.formation_family
        Amenity.BIKE -> R.string.formation_bike
    },
)

// Formation strip with the car readout. The rotary input steps a highlighted car once a
// tap on the strip has taken it, since it otherwise scrolls the tracking screen.
@Composable
fun FormationDiagramWear(formation: Formation, modifier: Modifier = Modifier) {
    var cursor by remember(formation) { mutableStateOf<Int?>(null) }
    var steppedAt by remember(formation) { mutableLongStateOf(0L) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var rotary by remember { mutableFloatStateOf(0f) }
    val focus = remember { FocusRequester() }
    val stepPx = with(LocalDensity.current) { 24.dp.toPx() }
    val count = formation.wagons.size

    fun select(car: Int) {
        cursor = car
        steppedAt = System.currentTimeMillis()
        now = steppedAt
    }

    LaunchedEffect(cursor, steppedAt) {
        while (cursor != null) {
            now = System.currentTimeMillis()
            if (readoutLeft(now - steppedAt) <= 0f) cursor = null
            delay(100)
        }
    }

    BackHandler(enabled = cursor != null) { cursor = null }

    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val strip = remember(formation, maxWidth) {
                FormationStrip(maxWidth.value, formation.wagons.map { it.noPassageAfter })
            }
            val density = LocalDensity.current
            FormationStripWear(
                formation = formation,
                strip = strip,
                cursor = cursor,
                modifier = Modifier
                    .focusRequester(focus)
                    .onRotaryScrollEvent { event ->
                        val current = cursor ?: return@onRotaryScrollEvent false
                        rotary += event.verticalScrollPixels
                        if (kotlin.math.abs(rotary) >= stepPx) {
                            select(stepCar(current, if (rotary > 0) 1 else -1, count))
                            rotary = 0f
                        }
                        true
                    }
                    .focusable()
                    .pointerInput(strip) {
                        detectTapGestures { offset ->
                            val x = with(density) { offset.x.toDp().value }
                            select(strip.carAt(x) ?: stepCar(cursor, 1, count))
                            rotary = 0f
                            focus.requestFocus()
                        }
                    },
            )
        }
        cursor?.let { car ->
            FormationReadoutWear(
                wagon = formation.wagons[car],
                left = readoutLeft(now - steppedAt),
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

// The train as a row of cars: nose and arrow on the left at the first car, a red bar
// where there is no way through, a colour line below each car per amenity, numbers or
// ranges on the cars and sector letters underneath.
@Composable
fun FormationStripWear(formation: Formation, strip: FormationStrip, cursor: Int?, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val scale = LocalDensity.current.density
    val wagons = formation.wagons
    val labels = remember(formation, strip, scale) {
        numberLabels(
            wagons.map { it.number },
            wagons.map { it.wagonClass },
            wagons.map { it.noPassageAfter },
        ) { label, a, b -> strip.fits(measurer.measure(label, labelStyle).size.width / scale, a, b) }
    }

    Canvas(modifier.fillMaxWidth().height(STRIP_HEIGHT.dp)) {
        val u = density
        drawNose(strip, u)
        wagons.forEachIndexed { i, wagon ->
            val car = strip.cars[i]
            val left = car.start * u
            val w = strip.carWidth * u
            if (i == cursor) {
                drawRect(Color.White, Offset(left - 1.5f * u, (CAR_TOP - 1.5f) * u), Size(w + 3f * u, (CAR_HEIGHT + 3f) * u))
            }
            val alpha = if (wagon.closed) 0.4f else 1f
            drawRect(bodyColour, Offset(left, CAR_TOP * u), Size(w, CAR_HEIGHT * u), alpha = alpha)
            if (wagon.wagonClass == 1 || wagon.mixedClass) {
                val stripe = if (wagon.mixedClass) w / 2 else w
                drawRect(firstClassColour, Offset(left, CAR_TOP * u), Size(stripe, 2.5f * u), alpha = alpha)
            }
            val found = if (wagon.closed) emptyList() else amenities(wagon.features)
            if (found.isNotEmpty()) {
                val seg = (w - 2f * u * (found.size - 1)) / found.size
                found.forEachIndexed { q, amenity ->
                    drawRect(amenity.colour, Offset(left + q * (seg + 2f * u), LINE_TOP * u), Size(seg, LINE_HEIGHT * u))
                }
            }
            if (wagon.noPassageAfter && i < wagons.lastIndex) {
                val mid = (car.endInclusive + strip.slot / 2) * u
                drawRect(
                    breakColour,
                    Offset(mid - 1.5f * u, (CAR_TOP - 2f) * u),
                    Size(3f * u, (LINE_TOP + LINE_HEIGHT - CAR_TOP + 2f) * u),
                )
            }
        }

        val spans = labels ?: wagons.indices.map { CarLabel(it, it, wagons[it].number.toString()) }
        for (label in spans) {
            val text = measurer.measure(label.text, labelStyle)
            val mid = (strip.cars[label.first].start + strip.cars[label.last].endInclusive) / 2 * u
            drawText(text, topLeft = Offset(mid - text.size.width / 2f, (CAR_TOP + CAR_HEIGHT / 2 + 0.75f) * u - text.size.height / 2f))
        }

        var i = 0
        while (i < wagons.size) {
            var j = i + 1
            while (j < wagons.size && wagons[j].sector == wagons[i].sector) j++
            val mid = (strip.cars[i].start + strip.cars[j - 1].endInclusive) / 2 * u
            if (wagons[i].sector.isNotEmpty()) {
                val text = measurer.measure(wagons[i].sector, sectorStyle)
                drawText(text, topLeft = Offset(mid - text.size.width / 2f, SECTOR_TOP * u))
            }
            if (j < wagons.size) {
                val edge = (strip.cars[j - 1].endInclusive + strip.cars[j].start) / 2 * u
                drawRect(tickColour, Offset(edge - 0.5f * u, TICK_TOP * u), Size(1f * u, 4f * u))
            }
            i = j
        }
    }
}

private fun DrawScope.drawNose(strip: FormationStrip, u: Float) {
    val end = strip.nose * u
    val top = CAR_TOP * u
    val bottom = (CAR_TOP + CAR_HEIGHT) * u
    val nose = Path().apply {
        moveTo(end, top)
        lineTo(end, bottom)
        lineTo(1f * u, bottom)
        quadraticTo(0f, top + (bottom - top) * 0.2f, end * 0.55f, top)
        close()
    }
    drawPath(nose, bodyColour)
    val cy = (top + bottom) / 2
    val cx = end * 0.55f
    val z = 3f * u
    val arrow = Path().apply {
        moveTo(cx - z, cy)
        lineTo(cx + z * 0.6f, cy - z)
        lineTo(cx + z * 0.6f, cy + z)
        close()
    }
    drawPath(arrow, Color.White)
}

// One line under the strip while a car is highlighted: number, sector, each amenity's
// colour beside its icon as the legend, and a ring that drains until the readout clears.
@Composable
fun FormationReadoutWear(wagon: FormationWagon, left: Float, modifier: Modifier = Modifier) {
    val description = stringResource(R.string.formation_car_fmt, wagon.number, wagon.sector)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = modifier.semantics { contentDescription = description },
    ) {
        Text("${wagon.number}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        if (wagon.sector.isNotEmpty()) {
            Text(wagon.sector, color = sectorColour, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
        for (amenity in amenities(wagon.features)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Box(Modifier.size(7.dp, 3.dp).background(amenity.colour))
                Icon(amenity.icon(), contentDescription = amenity.label(), tint = Color.White, modifier = Modifier.size(13.dp))
            }
        }
        Canvas(Modifier.size(10.dp)) {
            val stroke = 1.5.dp.toPx()
            val inset = Offset(stroke / 2, stroke / 2)
            val arc = Size(size.width - stroke, size.height - stroke)
            drawArc(bodyColour, 0f, 360f, false, inset, arc, style = Stroke(stroke))
            if (left > 0f) drawArc(Color.White, -90f, 360f * left, false, inset, arc, style = Stroke(stroke))
        }
    }
}
