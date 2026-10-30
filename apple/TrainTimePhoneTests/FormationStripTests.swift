import XCTest
@testable import TrainTimePhone

// The watch formation strip's number labels, over two live formations captured at Bern.
final class FormationStripTests: XCTestCase {
    struct Train {
        let numbers: [Int]
        let classes: [Int]
        let breaks: [Bool]
    }

    // Formation widths on the tracking screen: 40 mm and 49 mm screens less the side padding
    static let widths: [CGFloat] = [158, 201]

    // Sixteen cars in two units of eight
    static let sixteenCars = Train(
        numbers: [18, 17, 16, 15, 14, 13, 12, 11, 8, 7, 6, 5, 4, 3, 2, 1],
        classes: [2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1],
        breaks: (0..<16).map { $0 == 7 }
    )

    // Twelve cars, a unit of five numbered 20 to 16 then a unit of seven numbered 7 to 1
    static let twelveCars = Train(
        numbers: [20, 19, 18, 17, 16, 7, 6, 5, 4, 3, 2, 1],
        classes: [2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1],
        breaks: (0..<12).map { $0 == 4 }
    )

    private func assertCoversEveryCarOnce(_ t: Train, width: CGFloat, file: StaticString = #file, line: UInt = #line) {
        let strip = FormationStrip(width: width, breaks: t.breaks)
        // nil means each car carries its own number, which covers every car once
        guard let labels = strip.numberLabels(numbers: t.numbers, classes: t.classes, breaks: t.breaks) else { return }
        var seen = Array(repeating: 0, count: t.numbers.count)
        for label in labels {
            XCTAssertLessThanOrEqual(label.first, label.last, file: file, line: line)
            for i in label.first...label.last { seen[i] += 1 }
            for i in label.first..<label.last {
                XCTAssertFalse(t.breaks[i], "\(label.text) crosses a break at \(width) pt", file: file, line: line)
            }
        }
        XCTAssertEqual(seen, Array(repeating: 1, count: t.numbers.count), file: file, line: line)
    }

    func testSixteenCarsCoverEveryCarOnce() {
        for w in Self.widths { assertCoversEveryCarOnce(Self.sixteenCars, width: w) }
    }

    func testTwelveCarsCoverEveryCarOnce() {
        for w in Self.widths { assertCoversEveryCarOnce(Self.twelveCars, width: w) }
    }

    func testTwelveCarsAt40mmLabelEachUnitByRange() {
        let t = Self.twelveCars
        let strip = FormationStrip(width: 158, breaks: t.breaks)
        let labels = strip.numberLabels(numbers: t.numbers, classes: t.classes, breaks: t.breaks)
        XCTAssertEqual(labels?.map(\.text), ["20–16", "7–3", "2–1"])
    }

    func testSixteenCarsNeedRangesOnEveryWatch() {
        let t = Self.sixteenCars
        for w in Self.widths {
            XCTAssertNotNil(FormationStrip(width: w, breaks: t.breaks).numberLabels(numbers: t.numbers, classes: t.classes, breaks: t.breaks))
        }
    }

    func testShortTrainNumbersEveryCar() {
        let breaks = Array(repeating: false, count: 7)
        let strip = FormationStrip(width: 158, breaks: breaks)
        XCTAssertNil(strip.numberLabels(numbers: [7, 6, 5, 4, 3, 2, 1], classes: [2, 2, 2, 2, 1, 1, 1], breaks: breaks))
    }

    func testCarsShrinkToFitTheWidth() {
        let t = Self.sixteenCars
        for w in Self.widths {
            let strip = FormationStrip(width: w, breaks: t.breaks)
            XCTAssertLessThanOrEqual(strip.spans.last!.x1, w)
            XCTAssertEqual(strip.breakX(after: 7) - strip.spans[7].x1, FormationStrip.slot / 2)
        }
    }

    func testAmenitiesInSegmentOrder() {
        let wagon = FormationWagon(position: 1, number: 1, wagonClass: 2, sector: "A",
                                   features: ["bike", "low_floor", "wheelchair", "restaurant"], closed: false)
        XCTAssertEqual(FormationAmenity.of(wagon), [.restaurant, .wheelchair, .bike])
    }

    func testReadoutRingDrains() {
        XCTAssertEqual(FormationReadout.left(elapsed: 0), 1)
        XCTAssertEqual(FormationReadout.left(elapsed: 2.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(FormationReadout.left(elapsed: 5), 0)
        XCTAssertEqual(FormationReadout.left(elapsed: 9), 0)
    }
}
