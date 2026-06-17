import SnapshotTesting
import SwiftUI
import UIKit
import WidgetKit
import XCTest

// Visual regression for the WidgetKit entry views across families (light + dark). These views are
// widget-extension-only, so this target compiles the widget sources directly (no @testable import).
// This is the iOS counterpart to coverage Android can't do: Glance compiles to RemoteViews, which
// Roborazzi can't render, so the widget's visual lives here. Recorded on the build host, verified in CI.

final class WidgetEntrySnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_718_000_000)
    private var nowTs: Int { Int(now.timeIntervalSince1970) }

    private func wdep(_ line: String, _ dest: String, in offset: Int, delay: Int = 0) -> WidgetDeparture {
        WidgetDeparture(destination: dest, departureTimestamp: nowTs + offset, delay: delay,
                        platform: "3", platformChanged: false, lineNumber: line)
    }

    private func result() -> WidgetFetchResult {
        let bern = WidgetStation(id: "8507000", name: "Bern", departures: [
            wdep("IC8", "Brig", in: 540),
            wdep("IR16", "Zürich HB", in: 300),
            wdep("IC6", "Basel SBB", in: 720, delay: 2),
            wdep("RE1", "Luzern", in: 900),
            wdep("S1", "Thun", in: 1200),
        ])
        return WidgetFetchResult(train: [bern], bus: [], tram: [], special: [],
                                 selectedModeRaw: TransportMode.train.rawValue,
                                 selectedStationIndex: 0, fetchTime: now.timeIntervalSince1970)
    }

    private func entry(dormant: Bool) -> DepartureEntry {
        let favs = [Favourite(stationId: "8507000", stationName: "Bern", lineNumber: "IC8", destination: "Brig")]
        return DepartureEntry.make(date: now, result: result(), favourites: favs,
                                   isDormant: dormant, hideFavouritesBlock: false)
    }

    private func widget(_ family: WidgetFamily, dormant: Bool = false) -> AnyView {
        // widgetFamily is a read-only environment key; WidgetPreviewContext is the supported way
        // to render a specific family.
        AnyView(WidgetEntryView(entry: entry(dormant: dormant)).previewContext(WidgetPreviewContext(family: family)))
    }

    private func assertLightDark(_ view: AnyView, _ name: String, _ width: CGFloat, _ height: CGFloat,
                                 file: StaticString = #file, testName: String = #function, line: UInt = #line) {
        for (suffix, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            assertSnapshot(
                of: view,
                as: .image(precision: 0.99, perceptualPrecision: 0.97,
                           layout: .fixed(width: width, height: height),
                           traits: .init(userInterfaceStyle: style)),
                named: "\(name)_\(suffix)", file: file, testName: testName, line: line
            )
        }
    }

    func testSmallActive() { assertLightDark(widget(.systemSmall), "widget_small_active", 158, 158) }
    func testMediumActive() { assertLightDark(widget(.systemMedium), "widget_medium_active", 338, 158) }
    func testLargeActive() { assertLightDark(widget(.systemLarge), "widget_large_active", 338, 354) }
    func testMediumDormant() { assertLightDark(widget(.systemMedium, dormant: true), "widget_medium_dormant", 338, 158) }
    func testAccessoryRectangular() { assertLightDark(widget(.accessoryRectangular), "widget_accessory_rect", 160, 72) }
}
