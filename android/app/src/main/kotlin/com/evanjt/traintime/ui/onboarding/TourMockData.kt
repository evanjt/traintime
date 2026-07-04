package com.evanjt.traintime.ui.onboarding

import com.evanjt.traintime.data.model.Departure
import com.evanjt.traintime.data.model.FocusedDeparture
import com.evanjt.traintime.data.model.Formation
import com.evanjt.traintime.data.model.FormationWagon
import com.evanjt.traintime.data.model.Station
import com.evanjt.traintime.data.model.TransportMode

// Deterministic "Bern Bahnhof" world for the walkthrough. No network, no view
// model, no DataStore — every surface in the tour is driven from here so the
// demo is identical on every launch and never touches the user's real data.
object TourMockData {
    const val STATION_ID = "8507000"
    const val STATION_NAME = "Bern Bahnhof"

    // Timestamps hang off a base instant captured once per tour, so the minutes
    // column and the tracking countdown tick down naturally during the demo.
    fun departures(base: Long): List<Departure> = listOf(
        dep("Zürich HB", 4, base, 4, delay = 0, platform = "7", line = "IC1", cat = "IC"),
        dep("Brig", 6, base, 6, delay = 3, platform = "8", line = "IC8", cat = "IC"),
        dep("Luzern", 9, base, 9, delay = 0, platform = "5", line = "IR15", cat = "IR"),
        dep("Thun", 11, base, 11, delay = 0, platform = "12", platChanged = true, line = "RE", cat = "RE"),
        dep("Fribourg", 14, base, 14, delay = 0, platform = "2", line = "S1", cat = "S"),
        dep("Köniz", -1, base, -1, delay = 0, platform = "1", line = "S5", cat = "S"),
    )

    // The departure the tour tells the user to tap (step 2) and tracks.
    const val TRACK_LINE = "IC1"

    // The departure the tour tells the user to star (step 3) — a regular row a
    // few down, so starring visibly lifts it into the favourites block.
    const val FAVOURITE_LINE = "IR15"

    fun focused(base: Long): FocusedDeparture = FocusedDeparture(
        destination = "Zürich HB",
        departureTimestamp = base + 4 * 60,
        lineNumber = "IC1",
        category = "IC",
        trainNumber = "726",
        operatorRef = "sbb",
        delay = 0,
        platform = "7",
        platformChanged = false,
    )

    val formation: Formation = Formation(
        track = "7",
        sectors = listOf("A", "B", "C", "D"),
        wagons = listOf(
            FormationWagon(1, 1, wagonClass = 1, sector = "A", features = listOf("business"), closed = false),
            FormationWagon(2, 2, wagonClass = 1, sector = "A", features = emptyList(), closed = false),
            FormationWagon(3, 3, wagonClass = 2, sector = "B", features = listOf("restaurant"), closed = false),
            FormationWagon(4, 4, wagonClass = 2, sector = "C", features = listOf("wheelchair"), closed = false),
            FormationWagon(5, 5, wagonClass = 2, sector = "D", features = listOf("family"), closed = false),
        ),
    )

    // Nearby stations for the pinning step, in distance order. Bern Bahnhof sits
    // third — pinning it bubbles it to the top, which is the lesson.
    val nearbyStations: List<Station> = listOf(
        station("8590010", "Bern, Bärenplatz", 120.0, TransportMode.TRAM),
        station("8590011", "Bern, Bundesplatz", 190.0, TransportMode.BUS),
        station(STATION_ID, STATION_NAME, 260.0, TransportMode.TRAIN),
        station("8590012", "Bern, Hirschengraben", 340.0, TransportMode.TRAM),
        station("8507005", "Bern Wankdorf", 1900.0, TransportMode.TRAIN),
    )

    private fun dep(
        dest: String,
        min: Int,
        base: Long,
        offsetMin: Int = min,
        delay: Int,
        platform: String,
        platChanged: Boolean = false,
        line: String,
        cat: String,
    ) = Departure(
        destination = dest,
        minutesUntil = min,
        departureTimestamp = base + offsetMin * 60,
        delay = delay,
        platform = platform,
        platformChanged = platChanged,
        lineNumber = line,
        category = cat,
        trainNumber = null,
        operatorRef = null,
    )

    private fun station(id: String, name: String, dist: Double, mode: TransportMode) =
        Station(id = id, name = name, lat = 46.9489, lon = 7.4399, mode = mode, dist = dist)
}
