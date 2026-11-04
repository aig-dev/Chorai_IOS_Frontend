import XCTest
@testable import CoreFlow

final class ExploreSearchSwipeTests: XCTestCase {
    func testHorizontalDragKeepsExistingPreviousAndNextDirections() {
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: 101, vertical: 0), .previous)
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: -101, vertical: 0), .next)
    }

    func testVerticalAndDiagonalScrollCannotChangeSearchResult() {
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: 130, vertical: 260), .cancel)
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: -130, vertical: -260), .cancel)
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: 160, vertical: 160), .cancel)
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: 0, vertical: 400), .cancel)
    }

    func testShortDragAndExactThresholdReturnToTheCurrentResult() {
        for distance in [-100.0, -80, 0, 80, 100] {
            XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: distance, vertical: 0), .cancel)
        }
        XCTAssertEqual(ExploreSearchSwipe.resolve(horizontal: -100.1, vertical: 20), .next)
    }
}
