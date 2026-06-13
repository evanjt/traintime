package com.evanjt.traintime.data.model

import kotlinx.serialization.Serializable

@Serializable
data class Favourite(
    val stationId: String,
    val stationName: String,
    val lineNumber: String,
    val destination: String,
) {
    val id: String get() = "$stationId:$lineNumber:$destination"

    val displayString: String get() = "$lineNumber → $destination @ $stationName"
}
