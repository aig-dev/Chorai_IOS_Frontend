import Foundation
import XCTest
@testable import CoreFlow

final class RecentCardReadsTests: XCTestCase {
    func testReopeningKeepsOnlyTheMostRecentlyReadCards() {
        let reads = RecentCardReads<String>(capacity: 2)
        reads.insert("first", for: "a")
        reads.insert("second", for: "b")
        XCTAssertEqual(reads.value(for: "a"), "first")
        reads.insert("third", for: "c")
        XCTAssertNil(reads.value(for: "b"))
        XCTAssertEqual(reads.value(for: "a"), "first")
    }

    func testCardRemovalAndSessionChangeEvictAllMatchingReadData() {
        let details = RecentCardReads<String>()
        let comments = RecentCardReads<[String]>()
        details.insert("private body", for: "a")
        comments.insert(["private reply"], for: "a")
        details.insert("other note", for: "b")
        NotificationCenter.default.post(name: .cardReadInvalidated, object: "a")
        XCTAssertNil(details.value(for: "a"))
        XCTAssertNil(comments.value(for: "a"))
        XCTAssertEqual(details.value(for: "b"), "other note")
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        XCTAssertNil(details.value(for: "b"))
    }
}
