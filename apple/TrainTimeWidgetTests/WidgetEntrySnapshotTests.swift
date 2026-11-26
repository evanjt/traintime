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
    // Goldens are recorded on an iPhone. Text metrics differ by device, so other idioms skip them.
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "snapshot goldens are recorded on an iPhone")
    }

    private let now = Date(timeIntervalSince1970: 1_718_000_000)
    private var nowTs: Int { Int(now.timeIntervalSince1970) }

    private func wdep(_ line: String, _ dest: String, in offset: Int, delay: Int = 0) -> WidgetDeparture {
        WidgetDeparture(destination: dest, departureTimestamp: nowTs + offset, delay: delay,
                        platform: "3", platformChanged: false, lineNumber: line)
    }

    private var board: [WidgetDeparture] {
        [
            wdep("IC8", "Brig", in: 540),
            wdep("IR16", "Zürich HB", in: 300),
            wdep("IC6", "Basel SBB", in: 720, delay: 2),
            wdep("RE1", "Luzern", in: 900),
            wdep("S1", "Thun", in: 1200),
        ]
    }

    private var longNames: [WidgetDeparture] {
        [
            wdep("IR15", "Genève-Aéroport", in: 540),
            wdep("S3", "La Chaux-de-Fonds", in: 300),
            wdep("IC6", "Basel SBB", in: 720),
        ]
    }

    private func entry(_ departures: [WidgetDeparture], favourite: Int = 0, dormant: Bool) -> DepartureEntry {
        let bern = WidgetStation(id: "8507000", name: "Bern", departures: departures)
        let result = WidgetFetchResult(train: [bern], bus: [], tram: [], special: [],
                                       selectedModeRaw: TransportMode.train.rawValue,
                                       selectedStationIndex: 0, fetchTime: now.timeIntervalSince1970)
        let fav = departures[favourite]
        let favs = [Favourite(stationId: "8507000", stationName: "Bern",
                              lineNumber: fav.lineNumber, destination: fav.destination)]
        return DepartureEntry.make(date: now, result: result, favourites: favs,
                                   isDormant: dormant, hideFavouritesBlock: false, outsideSwitzerland: false)
    }

    // The family goes in as a parameter: `widgetFamily` cannot be set from a test, and a view
    // that reads it here draws the medium layout whatever family is asked for.
    private func widget(_ family: WidgetFamily, dormant: Bool = false) -> AnyView {
        AnyView(WidgetFamilyView(entry: entry(board, dormant: dormant), family: family))
    }

    // A small widget as a host that insets its content draws it: the canvas, the host's
    // margin, then the view.
    private func hostedSmall(dormant: Bool = false) -> AnyView {
        AnyView(
            WidgetFamilyView(entry: entry(longNames, favourite: 1, dormant: dormant), family: .systemSmall,
                             hostMargin: WidgetCanvas.hostMargin)
                .padding(WidgetCanvas.hostMargin)
        )
    }

    // Clock text follows the locale and zone, so both are fixed rather than taken from the machine
    private func assertLightDark(_ view: AnyView, _ name: String, _ width: CGFloat, _ height: CGFloat,
                                 locale: String = "en_GB",
                                 file: StaticString = #file, testName: String = #function, line: UInt = #line) {
        let pinned = AnyView(view
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Zurich")!))
        for (suffix, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            assertSnapshot(
                of: pinned,
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

    // Scenario: long destinations on the narrowest small canvas.
    // Expected behaviour: two departures, each destination on its own line under its countdown.
    func testSmallActiveNarrowestCanvas() {
        assertLightDark(hostedSmall(), "widget_small_narrowest_active", WidgetCanvas.narrowestSmall, WidgetCanvas.narrowestSmall)
    }

    func testSmallDormantNarrowestCanvas() {
        assertLightDark(hostedSmall(dormant: true), "widget_small_narrowest_dormant", WidgetCanvas.narrowestSmall, WidgetCanvas.narrowestSmall)
    }

    // Scenario: a 12-hour clock on the narrowest small canvas.
    // Expected behaviour: the station name stays whole and the time drops its "as of" words.
    func testSmallDormantNarrowestCanvasTwelveHourClock() {
        assertLightDark(hostedSmall(dormant: true), "widget_small_narrowest_dormant_12h", WidgetCanvas.narrowestSmall,
                        WidgetCanvas.narrowestSmall, locale: "en_US")
    }
}

/// The narrowest canvas a small widget is laid out on, and the margin its host insets the
/// content by, in points. An iPad mini home screen measured 140.7 and 15.5.
enum WidgetCanvas {
    static let narrowestSmall: CGFloat = 141
    static let hostMargin: CGFloat = 16
}

final class WidgetRowMetricsTests: XCTestCase {
    private func roundedBoldWidth(_ text: String, size: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func pillWidth(_ label: String, size: CGFloat, style: Font.TextStyle?) -> CGFloat {
        let host = UIHostingController(rootView: LinePill(label, fill: .blue, fontSize: size, relativeTo: style))
        return host.sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
    }

    func testLinePillIsOneWidthForEveryLabelInEveryFamily() {
        let labels = ["S3", "IR95", "BEG", "16", "V41", "RE33X", "ICE1234"]
        for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
            let m = WidgetRowMetrics.of(family)
            let widths = labels.map { pillWidth($0, size: m.lineSize, style: m.lineStyle) }
            XCTAssertEqual(widths, labels.map { _ in widths[0] }, "\(family)")
        }
    }

    func testSmallWidgetAddsNoInsetInsideAHostMargin() {
        XCTAssertEqual(WidgetRowMetrics.inset(.systemSmall, hostMargin: 16), 0)
        XCTAssertEqual(WidgetRowMetrics.inset(.systemSmall, hostMargin: 5), 7)
        XCTAssertEqual(WidgetRowMetrics.inset(.systemSmall, hostMargin: 0), 12)
        XCTAssertEqual(WidgetRowMetrics.inset(.systemMedium, hostMargin: 16), 12)
        XCTAssertEqual(WidgetRowMetrics.inset(.systemLarge, hostMargin: 16), 12)
    }

    private var narrowestSmallRow: CGFloat {
        let host = WidgetCanvas.hostMargin
        return WidgetCanvas.narrowestSmall - 2 * (host + WidgetRowMetrics.inset(.systemSmall, hostMargin: host))
    }

    func testNarrowestSmallRowStacksTheDestination() {
        XCTAssertTrue(WidgetRowMetrics.of(.systemSmall, rowWidth: narrowestSmallRow).stacksDestination)
        XCTAssertFalse(WidgetRowMetrics.of(.systemSmall, rowWidth: 126).stacksDestination)
        for family in [WidgetFamily.systemMedium, .systemLarge] {
            XCTAssertFalse(WidgetRowMetrics.of(family, rowWidth: narrowestSmallRow).stacksDestination, "\(family)")
        }
    }

    func testSingleLineSmallRowHoldsANameAtEveryWidth() {
        let font = UIFont.preferredFont(forTextStyle: .subheadline,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let name = ("Luzern" as NSString).size(withAttributes: [.font: font]).width
        for width in stride(from: narrowestSmallRow, through: 160, by: 1) {
            let m = WidgetRowMetrics.of(.systemSmall, rowWidth: width)
            if m.stacksDestination { continue }
            XCTAssertGreaterThanOrEqual(width - m.fixedRowWidth, name * m.destMinScale, "row \(width)")
        }
    }

    func testEveryMinutesLabelFitsItsColumnInEveryLanguage() {
        // A label measured within 2pt of its column still truncated on the home screen.
        let margin: CGFloat = 2
        let labels = ["now", "jetzt", "part", "ora", "gone", "weg", "parti", "perso", "59'"]
        for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
            let m = WidgetRowMetrics.of(family)
            for label in labels {
                let smallest = roundedBoldWidth(label, size: m.minutesSize) * m.minutesMinScale + margin
                XCTAssertLessThanOrEqual(smallest, m.minutesWidth, "\(label) in \(family)")
            }
        }
    }
}
