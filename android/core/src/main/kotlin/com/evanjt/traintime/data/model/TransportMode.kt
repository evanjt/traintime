package com.evanjt.traintime.data.model

import androidx.annotation.StringRes
import com.evanjt.traintime.core.R
import kotlinx.serialization.Serializable

@Serializable
enum class TransportMode(val raw: Int) {
    TRAIN(0),
    BUS(1),
    TRAM(2),
    SPECIAL(3);

    @get:StringRes
    val labelRes: Int
        get() = when (this) {
            TRAIN -> R.string.mode_train
            BUS -> R.string.mode_bus
            TRAM -> R.string.mode_tram
            SPECIAL -> R.string.mode_special
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
