import XCTest
@testable import TrainTimePhone

final class FavouritesTests: XCTestCase {
    private func dep(_ line: String, _ dest: String, _ ts: Int) -> Departure {
        Departure(
            destination: dest, minutesUntil: 5, departureTimestamp: ts, delay: 0,
            platform: "1", platformChanged: false, lineNumber: line, category: "IC",
            trainNumber: nil, operatorRef: nil,
        )
    }

    func testMergingInsertsMissingFavouritesInTimeOrder() {
        let merged = FavouritesStore().merging(
            favourites: [dep("IC8", "Brig", 1000)],
            into: [dep("S3", "Villeneuve", 1500)],
        )
        XCTAssertEqual(merged.map(\.lineNumber), ["IC8", "S3"])
    }

    func testMergingKeepsRegularWhenFavouriteAlreadyPresent() {
        let regular = [dep("IC8", "Brig", 1000), dep("S3", "Villeneuve", 1500)]
        let merged = FavouritesStore().merging(favourites: [dep("IC8", "Brig", 1000)], into: regular)
        XCTAssertEqual(merged.count, 2)
    }
}
