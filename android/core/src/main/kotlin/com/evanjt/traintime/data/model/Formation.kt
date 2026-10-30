package com.evanjt.traintime.data.model

data class FormationWagon(
    val position: Int,
    val number: Int,
    val wagonClass: Int, // 1 or 2
    val sector: String,
    val features: List<String>, // "wheelchair", "restaurant", "family", "business", "low_floor", "bike"
    val closed: Boolean,
    val noPassageAfter: Boolean = false, // no way through to the next car
    val mixedClass: Boolean = false, // first and second class in one car
)

data class Formation(
    val track: String,
    val sectors: List<String>,
    val wagons: List<FormationWagon>,
) {
    companion object {
        val railCategories = setOf(
            "IR", "IC", "EC", "ICE", "TGV", "RJX", "RE", "R", "S", "PE", "EXT", "NJ", "EN",
        )

        fun isRailCategory(category: String): Boolean = category in railCategories
    }
}
