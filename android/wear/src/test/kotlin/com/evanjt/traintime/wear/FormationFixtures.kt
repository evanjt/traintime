package com.evanjt.traintime.wear

import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon

// Live formations at Bern, front first as the feed lists them at the boarding stop.
object FormationFixtures {
    private fun car(
        position: Int,
        number: Int,
        wagonClass: Int,
        sector: String,
        vararg features: String,
        noPassageAfter: Boolean = false,
    ) = FormationWagon(position, number, wagonClass, sector, features.toList(), false, noPassageAfter)

    // Two units of eight with no way through after car 11
    val ic708 = Formation(
        track = "6",
        sectors = listOf("H", "G", "F", "E", "D", "C", "B", "A"),
        wagons = listOf(
            car(1, 18, 2, "H", "family", "low_floor"),
            car(2, 17, 2, "H", "low_floor", "bike"),
            car(3, 16, 2, "G", "low_floor", "bike"),
            car(4, 15, 2, "G", "wheelchair", "low_floor"),
            car(5, 14, 2, "F", "wheelchair", "low_floor"),
            car(6, 13, 1, "F", "low_floor", "bike"),
            car(7, 12, 1, "E", "low_floor", "bike"),
            car(8, 11, 1, "E", "business", "low_floor", "bike", noPassageAfter = true),
            car(9, 8, 2, "D", "family", "low_floor"),
            car(10, 7, 2, "D", "low_floor", "bike"),
            car(11, 6, 2, "C", "low_floor", "bike"),
            car(12, 5, 2, "B", "wheelchair", "low_floor"),
            car(13, 4, 2, "B", "wheelchair", "restaurant", "low_floor"),
            car(14, 3, 1, "B", "low_floor", "bike"),
            car(15, 2, 1, "A", "low_floor", "bike"),
            car(16, 1, 1, "A", "business", "low_floor", "bike"),
        ),
    )

    // A short unit of five ahead of a unit of seven, reversed at the boarding stop
    val ic977 = Formation(
        track = "8",
        sectors = listOf("A", "B", "C", "D", "E", "F", "G", "H"),
        wagons = listOf(
            car(1, 20, 2, "B", "family", "bike"),
            car(2, 19, 2, "B", "bike"),
            car(3, 18, 1, "C"),
            car(4, 17, 2, "C", "bike"),
            car(5, 16, 2, "D", "bike", noPassageAfter = true),
            car(6, 7, 2, "D", "family", "low_floor", "bike"),
            car(7, 6, 2, "E", "low_floor"),
            car(8, 5, 2, "E", "low_floor"),
            car(9, 4, 2, "F", "low_floor"),
            car(10, 3, 2, "F", "restaurant", "low_floor"),
            car(11, 2, 1, "G", "low_floor"),
            car(12, 1, 1, "G", "wheelchair", "business", "low_floor"),
        ),
    )
}
