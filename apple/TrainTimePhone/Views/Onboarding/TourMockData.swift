import Foundation

// Deterministic "Bern Bahnhof" world for the walkthrough. No network, no view model, no
// UserDefaults: every surface is driven from here so the demo is identical on each launch and
// never touches the user's real data. Peer of the Android TourMockData.kt.
enum TourMockData {
    static let stationId = "8507000"
    static let stationName = "Bern Bahnhof"

    // The departure the tour tells the user to tap (step 2) and the one to star (step 3).
    static let trackLine = "IC1"
    static let favouriteLine = "IR15"

    // Timestamps hang off a base instant captured once per tour, so the minutes column and the
    // tracking countdown tick down naturally during the demo.
    static func departures(base: Int) -> [Departure] {
        [
            dep("Zürich HB", 4, base, 4, delay: 0, platform: "7", line: "IC1", cat: "IC"),
            dep("Brig", 6, base, 6, delay: 3, platform: "8", line: "IC8", cat: "IC"),
            dep("Luzern", 9, base, 9, delay: 0, platform: "5", line: "IR15", cat: "IR"),
            dep("Thun", 11, base, 11, delay: 0, platform: "12", platChanged: true, line: "RE", cat: "RE"),
            dep("Fribourg", 14, base, 14, delay: 0, platform: "2", line: "S1", cat: "S"),
            dep("Köniz", -1, base, -1, delay: 0, platform: "1", line: "S5", cat: "S"),
        ]
    }

    static func focused(base: Int) -> FocusedDeparture {
        FocusedDeparture(
            destination: "Zürich HB",
            departureTimestamp: base + 4 * 60,
            lineNumber: "IC1",
            category: "IC",
            trainNumber: "726",
            operatorRef: "sbb",
            delay: 0,
            platform: "7",
            platformChanged: false
        )
    }

    static let formation = Formation(
        track: "7",
        sectors: ["A", "B", "C", "D"],
        wagons: [
            FormationWagon(position: 1, number: 1, wagonClass: 1, sector: "A", features: ["business"], closed: false),
            FormationWagon(position: 2, number: 2, wagonClass: 1, sector: "A", features: [], closed: false),
            FormationWagon(position: 3, number: 3, wagonClass: 2, sector: "B", features: ["restaurant"], closed: false),
            FormationWagon(position: 4, number: 4, wagonClass: 2, sector: "C", features: ["wheelchair"], closed: false),
            FormationWagon(position: 5, number: 5, wagonClass: 2, sector: "D", features: ["family"], closed: false),
        ]
    )

    // Nearby stations for the pinning step, in distance order. Bern Bahnhof sits third, so
    // pinning it bubbles it to the top, which is the lesson.
    static let nearbyStations: [Station] = [
        station("8590010", "Bern, Bärenplatz", 120, .tram),
        station("8590011", "Bern, Bundesplatz", 190, .bus),
        station(stationId, stationName, 260, .train),
        station("8590012", "Bern, Hirschengraben", 340, .tram),
        station("8507005", "Bern Wankdorf", 1900, .train),
    ]

    private static func dep(
        _ dest: String, _ min: Int, _ base: Int, _ offsetMin: Int,
        delay: Int, platform: String, platChanged: Bool = false, line: String, cat: String
    ) -> Departure {
        Departure(
            destination: dest,
            minutesUntil: min,
            departureTimestamp: base + offsetMin * 60,
            delay: delay,
            platform: platform,
            platformChanged: platChanged,
            lineNumber: line,
            category: cat,
            trainNumber: nil,
            operatorRef: nil
        )
    }

    private static func station(_ id: String, _ name: String, _ dist: Double, _ mode: TransportMode) -> Station {
        Station(id: id, name: name, lat: 46.9489, lon: 7.4399, mode: mode, dist: dist, embeddedDepartures: nil)
    }
}
