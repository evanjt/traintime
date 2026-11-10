import XCTest
@testable import TrainTimePhone

// The watch formation strip's number labels, over two live formations captured at Bern.
final class FormationStripTests: XCTestCase {
    struct Train {
        let numbers: [Int?]
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
        let labels = strip.numberLabels(numbers: t.numbers, classes: t.classes, breaks: t.breaks)
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
        XCTAssertEqual(labels.map(\.text), ["20–16", "7–3", "2–1"])
    }

    func testSixteenCarsNeedRangesOnEveryWatch() {
        let t = Self.sixteenCars
        for w in Self.widths {
            let labels = FormationStrip(width: w, breaks: t.breaks).numberLabels(numbers: t.numbers, classes: t.classes, breaks: t.breaks)
            XCTAssertTrue(labels.contains { $0.last > $0.first })
        }
    }

    func testShortTrainNumbersEveryCar() {
        let breaks = Array(repeating: false, count: 7)
        let strip = FormationStrip(width: 158, breaks: breaks)
        let labels = strip.numberLabels(numbers: [7, 6, 5, 4, 3, 2, 1], classes: [2, 2, 2, 2, 1, 1, 1], breaks: breaks)
        XCTAssertEqual(labels, (0..<7).map { FormationNumberLabel(first: $0, last: $0, text: "\(7 - $0)") })
    }

    func testTrainWithNoNumberedCarShowsNoNumbers() {
        let breaks = (0..<8).map { $0 == 3 }
        let strip = FormationStrip(width: 158, breaks: breaks)
        let labels = strip.numberLabels(numbers: Array(repeating: nil, count: 8), classes: [2, 2, 1, 2, 2, 2, 1, 2], breaks: breaks)
        XCTAssertEqual(labels, [])
    }

    // Scenario: the second and fifth cars carry no number in the feed.
    // Expected behaviour: only numbered cars are labelled, and no range runs across an unnumbered car.
    func testOnlyNumberedCarsAreLabelled() {
        var numbers = Self.sixteenCars.numbers
        numbers[1] = nil
        numbers[4] = nil
        let t = Train(numbers: numbers, classes: Self.sixteenCars.classes, breaks: Self.sixteenCars.breaks)
        for w in Self.widths {
            let labels = FormationStrip(width: w, breaks: t.breaks).numberLabels(numbers: t.numbers, classes: t.classes, breaks: t.breaks)
            var seen = Array(repeating: 0, count: 16)
            for label in labels { for i in label.first...label.last { seen[i] += 1 } }
            XCTAssertEqual(seen, numbers.map { $0 == nil ? 0 : 1 }, "at \(w) pt")
        }
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

    func testClosedCarCarriesNoNumberAndNoAmenities() {
        let open = FormationWagon(position: 1, number: 7, wagonClass: 2, sector: "C", features: ["bike"], closed: false)
        let closed = FormationWagon(position: 2, number: 8, wagonClass: 1, sector: "D",
                                    features: ["restaurant", "wheelchair"], closed: true)
        XCTAssertEqual(FormationStrip.labelNumbers([open, closed]), [7, nil])
        XCTAssertEqual(FormationAmenity.of(open), [.bike])
        XCTAssertEqual(FormationAmenity.of(closed), [])
    }

    func testReadoutRingDrains() {
        XCTAssertEqual(FormationReadout.left(elapsed: 0), 1)
        XCTAssertEqual(FormationReadout.left(elapsed: 2.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(FormationReadout.left(elapsed: 5), 0)
        XCTAssertEqual(FormationReadout.left(elapsed: 9), 0)
    }
}
