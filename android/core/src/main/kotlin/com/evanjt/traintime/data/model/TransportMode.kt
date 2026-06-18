package com.evanjt.traintime.data.model

import kotlinx.serialization.Serializable

@Serializable
enum class TransportMode(val raw: Int) {
    TRAIN(0),
    BUS(1),
    TRAM(2),
    SPECIAL(3);

    val label: String
        get() = when (this) {
            TRAIN -> "Train"
            BUS -> "Bus"
            TRAM -> "Tram"
            SPECIAL -> "Special"
        }

    /// Query param value for /v1/nearby; train is the server default.
    val apiParam: String?
        get() = when (this) {
            TRAIN -> null
            BUS -> "bus"
            TRAM -> "tram"
            SPECIAL -> "special"
        }

    companion object {
        fun fromRaw(raw: Int): TransportMode =
            entries.firstOrNull { it.raw == raw } ?: TRAIN
    }
}
