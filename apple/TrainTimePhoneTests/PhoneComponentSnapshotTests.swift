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

    private func assertLightDark(_ view: AnyView, _ name: String,
                                 file: StaticString = #file, testName: String = #function, line: UInt = #line) {
        for (suffix, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            assertSnapshot(
                of: view,
                as: .image(precision: 0.99, perceptualPrecision: 0.98,
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

    func testTourWatch() {
        let view = TourWatchCard()
            .padding(16)
            .frame(width: 360)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(view), "tour_watch")
    }

    func testTourWidget() {
        let view = TourWidgetMock()
            .padding(24)
            .background(Color(uiColor: .systemBackground))
        assertLightDark(AnyView(view), "tour_widget")
    }
}
