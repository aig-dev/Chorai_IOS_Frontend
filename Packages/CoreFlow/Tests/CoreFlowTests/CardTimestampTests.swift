import XCTest
@testable import CoreFlow

final class CardTimestampTests: XCTestCase {
    func testDateOnlyPreservesCalendarDateFromOffsetISO8601Timestamp() {
        XCTAssertEqual(
            CardTimestamp.dateOnly(from: "2026-08-14T12:00:12+08:00"),
            "2026-08-14"
        )
    }

    func testDateOnlyPreservesCalendarDateFromFractionalISO8601Timestamp() {
        XCTAssertEqual(
            CardTimestamp.dateOnly(from: "2024-03-09T16:00:00.123456Z"),
            "2024-03-09"
        )
    }
}
