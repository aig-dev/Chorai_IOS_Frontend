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

    func testInvalidAndMissingTimestampsKeepTheirOriginalDisplayValue() {
        for value in ["", "not-a-date", "2026-01-01", "2026-01-01T00:00:60Z"] {
            XCTAssertNil(CardTimestamp.parse(value), value)
            XCTAssertEqual(CardTimestamp.dateOnly(from: value), value)
        }
    }

    func testParsingPreservesLegacyFractionalPrecisionAndSourceCalendarDay() throws {
        let values = [
            ("2026-01-01T00:00:00.123456Z", 1767225600.123),
            ("2026-01-01T00:00:00.999999Z", 1767225600.999),
            ("2026-01-01T00:00:00.000001Z", 1767225600.0),
            ("2026-01-01T00:00:00+14:00", 1767175200.0),
            ("2026-01-01T00:00:00-12:00", 1767268800.0),
        ]
        for (text, seconds) in values {
            XCTAssertEqual(try XCTUnwrap(CardTimestamp.parse(text)).timeIntervalSince1970,
                           seconds, accuracy: 0.000001, text)
            XCTAssertEqual(CardTimestamp.dateOnly(from: text), "2026-01-01")
        }
    }

    func testParsingRetainsLegacyWhitespaceAndOffsetAcceptance() throws {
        for text in ["2026-01-01T08:00:00+0800", "2026-01-01T08:00:00+08",
                     " 2026-01-01T00:00:00Z"] {
            XCTAssertEqual(try XCTUnwrap(CardTimestamp.parse(text)).timeIntervalSince1970,
                           1767225600, accuracy: 0.000001, text)
        }
        XCTAssertEqual(CardTimestamp.dateOnly(from: " 2026-01-01T00:00:00Z"), " 2026-01-01")
    }

    func testParallelParsesMatchSerialResultsForValidAndInvalidInputs() async {
        let texts = ["2026-01-01T00:00:00Z", "2026-01-01T08:00:00.123456+08:00",
                     "2026-01-01T00:00:00-12:00", "invalid", "2026-01-01T00:00:60Z"]
        let expected = texts.map { CardTimestamp.parse($0) }
        await withTaskGroup(of: (Int, Date?).self) { group in
            for index in 0..<500 {
                let text = texts[index % texts.count]
                group.addTask { (index, CardTimestamp.parse(text)) }
            }
            for await (index, result) in group {
                XCTAssertEqual(result, expected[index % texts.count])
            }
        }
    }
}
