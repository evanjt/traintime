package com.evanjt.traintime.wear

import androidx.compose.ui.graphics.Color

// Watch amenities in the order their lines and readout swatches run. Hues shared with
// the other watches, distinct for normal, deutan and protan vision.
enum class Amenity(val feature: String, val colour: Color) {
    RESTAURANT("restaurant", Color(0xFFFF5555)),
    WHEELCHAIR("wheelchair", Color(0xFF00AAFF)),
    FAMILY("family", Color(0xFFFFFFFF)),
    BIKE("bike", Color(0xFF55FF00)),
}

fun amenities(features: List<String>): List<Amenity> =
    Amenity.entries.filter { it.feature in features }

// Car positions across a strip of the given width, front first from the left after the
// nose. Cars shrink to fit, a break takes a wider slot instead of the usual gap.
class FormationStrip(
    val width: Float,
    breaks: List<Boolean>,
    val nose: Float = 12f,
    val gap: Float = 2f,
    val slot: Float = 8f,
    maxCar: Float = 30f,
) {
    val carWidth: Float
    val cars: List<ClosedFloatingPointRange<Float>>

    init {
        val n = breaks.size.coerceAtLeast(1)
        val inner = breaks.dropLast(1)
        val slots = inner.count { it }
        val gaps = inner.size - slots
        carWidth = ((width - nose - gap - gaps * gap - slots * slot) / n).coerceAtMost(maxCar)
        var x = nose + gap
        cars = breaks.map { brk ->
            val car = x..(x + carWidth)
            x += carWidth + if (brk) slot else gap
            car
        }
    }

    // Whether text of the given width sits inside cars a..b with a little air either side
    fun fits(textWidth: Float, a: Int, b: Int): Boolean =
        textWidth <= cars[b].endInclusive - cars[a].start - 2f

    fun carAt(x: Float): Int? = cars.indexOfFirst { x >= it.start - gap / 2 && x <= it.endInclusive + gap / 2 }
        .takeIf { it >= 0 }
}

data class CarLabel(val first: Int, val last: Int, val text: String)

private fun rangeLabel(numbers: List<Int>, a: Int, b: Int) =
    if (b > a) "${numbers[a]}-${numbers[b]}" else numbers[a].toString()

// Every car's own number when all fit, otherwise a range per run of same-class cars,
// extended over the next run in the unit until it fits, so every car is covered and no
// label crosses a break. Null means per-car numbers. The same rule runs on every watch.
fun numberLabels(
    numbers: List<Int>,
    classes: List<Int>,
    breaks: List<Boolean>,
    fits: (label: String, first: Int, last: Int) -> Boolean,
): List<CarLabel>? {
    val n = numbers.size
    if (numbers.indices.all { fits(numbers[it].toString(), it, it) }) return null
    val out = mutableListOf<CarLabel>()
    var i = 0
    while (i < n) {
        var u = i
        while (u < n - 1 && !breaks[u]) u++
        var a = i
        while (a <= u) {
            var b = a
            while (b < u && classes[b + 1] == classes[a]) b++
            var label = rangeLabel(numbers, a, b)
            while (!fits(label, a, b) && b < u) {
                b++
                while (b < u && classes[b + 1] == classes[b]) b++
                label = rangeLabel(numbers, a, b)
            }
            // A tail that still does not fit joins the label before it in the same unit
            if (!fits(label, a, b)) {
                val prev = out.lastOrNull()
                if (prev != null && prev.last == a - 1 && prev.first >= i) {
                    a = prev.first
                    label = rangeLabel(numbers, a, b)
                    out.removeAt(out.lastIndex)
                }
            }
            if (!fits(label, a, b)) label = numbers[a].toString()
            out.add(CarLabel(a, b, label))
            a = b + 1
        }
        i = u + 1
    }
    return out
}

// The car readout stays this long after the last step
const val READOUT_MILLIS = 5_000L

// Share of the readout time left, 1 just after a step, 0 once it has gone
fun readoutLeft(elapsedMillis: Long): Float =
    (1f - elapsedMillis.toFloat() / READOUT_MILLIS).coerceIn(0f, 1f)

// Next highlighted car: entering from nothing starts at the end the step points away from
fun stepCar(current: Int?, step: Int, count: Int): Int =
    if (current == null) {
        if (step > 0) 0 else count - 1
    } else {
        ((current + step) % count + count) % count
    }
