import Foundation
import XCTest
import os
@testable import CoreFlow

@MainActor
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

    func testReplacementTouchesRecencyAndInvalidatingUnknownCardKeepsOtherReads() {
        let reads = RecentCardReads<String>(capacity: 2)
        reads.insert("a1", for: "a")
        reads.insert("b1", for: "b")
        reads.insert("a2", for: "a")
        reads.insert("c1", for: "c")
        NotificationCenter.default.post(name: .cardReadInvalidated, object: "unknown")
        XCTAssertEqual(reads.value(for: "a"), "a2")
        XCTAssertEqual(reads.value(for: "c"), "c1")
        XCTAssertNil(reads.value(for: "b"))
    }

    func testNonpositiveCapacityRetainsTheLatestSingleRead() {
        for capacity in [0, -1] {
            let reads = RecentCardReads<String>(capacity: capacity)
            reads.insert("a", for: "a")
            reads.insert("b", for: "b")
            XCTAssertNil(reads.value(for: "a"))
            XCTAssertEqual(reads.value(for: "b"), "b")
        }
    }

    func testBackgroundNotificationCompletesEvictionBeforePostingReturns() async {
        let reads = RecentCardReads<String>()
        reads.insert("private", for: "a")
        await Task.detached {
            NotificationCenter.default.post(name: .cardReadInvalidated, object: "a")
        }.value
        XCTAssertNil(reads.value(for: "a"))
        reads.insert("private", for: "b")
        await Task.detached {
            NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        }.value
        XCTAssertNil(reads.value(for: "b"))
    }

    func testNotificationObserversDoNotRetainTheirCache() {
        weak var released: RecentCardReads<String>?
        autoreleasepool {
            let reads = RecentCardReads<String>()
            reads.insert("private", for: "a")
            released = reads
        }
        XCTAssertNil(released)
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
    }

    func testBackgroundLastReleaseDestroysMainActorOwnedValuesOnMain() async {
        let released = expectation(description: "actor-owned value released")
        func makeCache() -> RecentCardReads<ReadLifetimeProbe> {
            let cache = RecentCardReads<ReadLifetimeProbe>()
            cache.insert(ReadLifetimeProbe {
                XCTAssertTrue(Thread.isMainThread)
                released.fulfill()
            }, for: "a")
            return cache
        }
        let held = OSAllocatedUnfairLock(uncheckedState: Optional(makeCache()))
        await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            held.withLock { $0 = nil }
        }.value
        await fulfillment(of: [released], timeout: 3)
    }

    func testDeinitializationRemovesBothNotificationRegistrations() {
        let center = ReadObservationCenter()
        autoreleasepool {
            let reads = RecentCardReads<String>(center: center)
            reads.insert("private", for: "a")
            XCTAssertEqual(center.observerCount, 2)
            center.post(name: .cardReadSessionDidChange, object: nil)
            XCTAssertNil(reads.value(for: "a"))
        }
        XCTAssertEqual(center.observerCount, 0)
    }
}

private final class ReadLifetimeProbe {
    private let released: @Sendable () -> Void
    init(released: @escaping @Sendable () -> Void) { self.released = released }
    deinit { released() }
}

// The superclass is Sendable; this test double's only added state is lock-protected.
private final class ReadObservationCenter: NotificationCenter, @unchecked Sendable {
    private let tokens = OSAllocatedUnfairLock(initialState: Set<ObjectIdentifier>())
    var observerCount: Int { tokens.withLock { $0.count } }

    override func addObserver(forName name: NSNotification.Name?, object obj: Any?,
                              queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        let token = super.addObserver(forName: name, object: obj, queue: queue, using: block)
        let id = ObjectIdentifier(token)
        tokens.withLock { _ = $0.insert(id) }
        return token
    }

    override func removeObserver(_ observer: Any) {
        super.removeObserver(observer)
        let id = ObjectIdentifier(observer as AnyObject)
        tokens.withLock { _ = $0.remove(id) }
    }
}
