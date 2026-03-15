package ch.traintime.shared.models

enum class TransportMode(val label: String, val materialIcon: String) {
    TRAIN("Train", "train"),
    BUS("Bus", "directions_bus"),
    TRAM("Tram", "tram"),
    SPECIAL("Special", "aerial_tramway");

    companion object {
        fun from(icon: String?): TransportMode = when (icon) {
            "bus" -> BUS
            "tram" -> TRAM
            "special" -> SPECIAL
            else -> TRAIN
        }
    }
}
