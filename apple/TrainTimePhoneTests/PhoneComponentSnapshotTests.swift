import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import TrainTimePhone

// Component-level visual regression (light + dark), mirroring Android's DepartureRowSnapshotTest +
// ComponentSnapshotTest. AppColors / system colours resolve through UITraitCollection, so light and
// dark are forced via the trait collection, not just the SwiftUI environment.
// Goldens are recorded on the build host and committed under __Snapshots__/; CI then verifies.

final class PhoneComponentSnapshotTests: XCTestCase {
    private let nowTs = 1_718_000_000

    private func dep(_ line: String, _ dest: String, min: Int, delay: Int = 0, gone: Bool = false) -> Departure {
        Departure(
            destination: dest, minutesUntil: gone ? -1 : min,
            departureTimestamp: nowTs + min * 60, delay: delay,
            platform: "3", platformChanged: false, lineNumber: line,
            category: "IC", trainNumber: nil, operatorRef: nil
        )
    }

    private func assertLightDark(_ view: AnyView, _ name: String, pixelPrecision: Float = 0.99,
                                 file: StaticString = #file, testName: String = #function, line: UInt = #line) {
        for (suffix, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            assertSnapshot(
                of: view,
                as: .image(precision: pixelPrecision, perceptualPrecision: 0.98,
                           layout: .sizeThatFits, traits: .init(userInterfaceStyle: style)),
                named: "\(name)_\(suffix)", file: file, testName: testName, line: line
            )
        }
    }

    func testDepartureRows() {
        let rows = VStack(spacing: 0) {
            PhoneDepartureRowView(departure: dep("IR15", "Luzern", min: 6), mode: .train)
            PhoneDepartureRowView(departure: dep("IC8", "Romanshorn", min: 8, delay: 1), mode: .train)
            PhoneDepartureRowView(departure: dep("S7", "Worb Dorf", min: 6), isFavourite: true, mode: .train)
            PhoneDepartureRowView(departure: dep("12", "Sion", min: 4), mode: .bus)
            PhoneDepartureRowView(departure: dep("IR95", "Genève", min: -1, gone: true), mode: .train)
        }
        .padding(.horizontal, 12)
        .frame(width: 360)
        .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(rows), "phone_departure_rows")
    }

    func testTrackingBar() {
        let bars = VStack(spacing: 14) {
            TrackingBarView(schedBuf: 4, effectBuf: 5, hasGPS: true)    // ahead
            TrackingBarView(schedBuf: -2, effectBuf: -1, hasGPS: true)  // behind
            TrackingBarView(schedBuf: 0, effectBuf: 0, hasGPS: true)    // on time
            TrackingBarView(schedBuf: 0, effectBuf: 0, hasGPS: false)   // no GPS
        }
        .padding(16)
        .frame(width: 320)
        .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(bars), "phone_tracking")
    }

    func testFormation() {
        let formation = Formation(
            track: "3", sectors: ["A", "B", "C"],
            wagons: [
                FormationWagon(position: 1, number: 1, wagonClass: 1, sector: "A", features: ["business"], closed: false),
                FormationWagon(position: 2, number: 2, wagonClass: 2, sector: "B", features: ["wheelchair", "restaurant"], closed: false),
                FormationWagon(position: 3, number: 3, wagonClass: 2, sector: "C", features: [], closed: false),
            ]
        )
        let view = FormationDiagramView(formation: formation)
            .padding(16)
            .frame(width: 360)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(view), "phone_formation")
    }

    // Twelve cars in two units with a no-passage break, as the 40 mm watch draws them
    func testWatchFormation() {
        let cars: [(Int, Int, String, [String])] = [
            (20, 2, "B", ["family", "bike"]), (19, 2, "B", ["bike"]), (18, 1, "C", []),
            (17, 2, "C", ["bike"]), (16, 2, "D", ["bike"]), (7, 2, "D", ["family", "low_floor", "bike"]),
            (6, 2, "E", ["low_floor"]), (5, 2, "E", ["low_floor"]), (4, 2, "F", ["low_floor"]),
            (3, 2, "F", ["restaurant", "low_floor"]), (2, 1, "G", ["low_floor"]), (1, 1, "G", ["wheelchair", "business"]),
        ]
        let wagons = cars.enumerated().map { i, c in
            FormationWagon(position: i + 1, number: c.0, wagonClass: c.1, sector: c.2, features: c.3,
                           closed: false, noPassageAfter: i == 4)
        }
        let formation = Formation(track: "7", sectors: ["B", "C", "D", "E", "F", "G"], wagons: wagons)
        let view = VStack(spacing: 6) {
            WatchFormationView(formation: formation)
            WatchFormationView(formation: formation, cursor: 9)
            WatchCarReadoutRow(wagon: wagons[9], left: 0.6)
        }
        .frame(width: 158)
        .padding(4)
        .background(Color.black)
        assertSnapshot(
            of: AnyView(view),
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .sizeThatFits,
                       traits: .init(userInterfaceStyle: .dark)),
            named: "watch_formation_40mm"
        )
    }

    // An S-Bahn of two four-car units whose cars the feed does not number, live at Bern
    func testUnnumberedFormation() {
        let cars: [(Int, String, [String], Bool)] = [
            (2, "A", ["low_floor"], false), (2, "A", ["wheelchair", "low_floor", "bike"], false),
            (1, "A", ["low_floor", "bike"], true), (2, "A", ["low_floor"], false),
            (2, "A", ["low_floor"], false), (2, "A", ["wheelchair", "low_floor", "bike"], false),
            (1, "B", ["low_floor", "bike"], true), (2, "B", ["low_floor"], false),
        ]
        let wagons = cars.enumerated().map { i, c in
            FormationWagon(position: i + 1, number: nil, wagonClass: c.0, sector: c.1, features: c.2,
                           closed: false, noPassageAfter: i == 3, mixedClass: c.3)
        }
        let formation = Formation(track: "13", sectors: ["A", "B", "C", "D", "E", "F"], wagons: wagons)
        let phone = FormationDiagramView(formation: formation)
            .padding(16)
            .frame(width: 360)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(phone), "phone_formation_unnumbered")
        let watch = VStack(spacing: 6) {
            WatchFormationView(formation: formation, cursor: 1)
            WatchCarReadoutRow(wagon: wagons[1], left: 0.6)
        }
        .frame(width: 158)
        .padding(4)
        .background(Color.black)
        assertSnapshot(
            of: AnyView(watch),
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .sizeThatFits,
                       traits: .init(userInterfaceStyle: .dark)),
            named: "watch_formation_unnumbered"
        )
    }

    func testFormationDoubleUnit() {
        let view = FormationDiagramView(formation: FormationFixtures.doubleUnit)
            .padding(16)
            .frame(width: 360)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(view), "phone_formation_double_unit")
    }

    func testFormationClosedAndMixedClass() {
        let formation = Formation(
            track: "4", sectors: ["A", "B"],
            wagons: [
                FormationWagon(position: 1, number: 21, wagonClass: 1, sector: "A", features: ["restaurant"], closed: true),
                FormationWagon(position: 2, number: 22, wagonClass: 1, sector: "A", features: ["wheelchair"], closed: false, mixedClass: true),
                FormationWagon(position: 3, number: 23, wagonClass: 2, sector: "B", features: ["kw"], closed: false),
            ]
        )
        let view = FormationDiagramView(formation: formation)
            .padding(16)
            .frame(width: 360)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(view), "phone_formation_closed_mixed")
    }

    func testTourWatch() {
        let view = TourWatchCard()
            .padding(16)
            .frame(width: 360)
            .background(Color(uiColor: .systemBackground))
        // The watch product photos downsample with different edge halos on the CI
        // renderer than on the recording host (~1.6% of pixels); the per-pixel
        // perceptual bar still guards real changes.
        assertLightDark(AnyView(view), "tour_watch", pixelPrecision: 0.96)
    }

    func testTourWidget() {
        let view = TourWidgetMock()
            .padding(24)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(view), "tour_widget")
    }
}
