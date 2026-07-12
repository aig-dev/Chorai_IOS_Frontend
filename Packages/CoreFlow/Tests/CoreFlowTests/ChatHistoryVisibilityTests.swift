import Foundation
import XCTest
@testable import CoreFlow

final class ChatHistoryVisibilityTests: XCTestCase {
    func testClearWritesOnlyActorScopedCutoff() {
        let persistence = InMemoryChatCutoffPersistence()
        let visibility = ChatHistoryVisibility(persistence: persistence)
        let cutoff = Date(timeIntervalSince1970: 100)

        visibility.clear(actorID: "human_a", at: cutoff)

        XCTAssertEqual(persistence.savedActorIDs, ["human_a"])
        XCTAssertEqual(persistence.cutoffDate(actorID: "human_a"), cutoff)
        XCTAssertNil(persistence.cutoffDate(actorID: "human_b"))
    }

    func testActivityAtOrBeforeCutoffIsHiddenAndPostCutoffIsVisible() {
        let persistence = InMemoryChatCutoffPersistence()
        let visibility = ChatHistoryVisibility(persistence: persistence)
        let cutoff = Date(timeIntervalSince1970: 100)
        visibility.clear(actorID: "human_a", at: cutoff)

        XCTAssertFalse(visibility.isVisible(timestamp: cutoff.addingTimeInterval(-1), actorID: "human_a"))
        XCTAssertFalse(visibility.isVisible(timestamp: cutoff, actorID: "human_a"))
        XCTAssertTrue(visibility.isVisible(timestamp: cutoff.addingTimeInterval(0.001), actorID: "human_a"))
    }

    func testMissingTimestampIsHiddenOnlyWhenCutoffExists() {
        let persistence = InMemoryChatCutoffPersistence()
        let visibility = ChatHistoryVisibility(persistence: persistence)

        XCTAssertTrue(visibility.isVisible(timestamp: nil, actorID: "human_a"))
        visibility.clear(actorID: "human_a", at: Date(timeIntervalSince1970: 100))
        XCTAssertFalse(visibility.isVisible(timestamp: nil, actorID: "human_a"))
    }

    func testAnotherActorIsIndependent() {
        let persistence = InMemoryChatCutoffPersistence()
        let visibility = ChatHistoryVisibility(persistence: persistence)
        visibility.clear(actorID: "human_a", at: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(visibility.isVisible(timestamp: Date(timeIntervalSince1970: 50), actorID: "human_a"))
        XCTAssertTrue(visibility.isVisible(timestamp: Date(timeIntervalSince1970: 50), actorID: "human_b"))
    }

    func testPostCutoffMessageMakesConversationVisible() {
        let persistence = InMemoryChatCutoffPersistence()
        let visibility = ChatHistoryVisibility(persistence: persistence)
        visibility.clear(actorID: "human_a", at: Date(timeIntervalSince1970: 100))
        let messageTimestamps = [
            Date(timeIntervalSince1970: 90),
            Date(timeIntervalSince1970: 101)
        ]

        let conversationVisible = messageTimestamps.contains {
            visibility.isVisible(timestamp: $0, actorID: "human_a")
        }

        XCTAssertTrue(conversationVisible)
    }

    func testISO8601HelperTreatsInvalidTimestampAsMissingAfterCutoff() {
        let persistence = InMemoryChatCutoffPersistence()
        let visibility = ChatHistoryVisibility(persistence: persistence)
        visibility.clear(actorID: "human_a", at: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(visibility.isVisible(timestampString: "not-a-date", actorID: "human_a"))
        XCTAssertTrue(
            visibility.isVisible(
                timestampString: "1970-01-01T00:01:41.000Z",
                actorID: "human_a"
            )
        )
    }

    func testUserDefaultsPersistenceStoresNamespacedPreciseCutoffsPerActor() {
        let suiteName = "ChatHistoryVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsChatHistoryCutoffPersistence(
            defaults: defaults,
            keyPrefix: "test.chat.cutoff"
        )
        let cutoff = Date(timeIntervalSince1970: 100.125)

        persistence.saveCutoff(cutoff, actorID: "human_a")

        XCTAssertEqual(persistence.cutoffRecord(actorID: "human_a"), .valid(cutoff))
        XCTAssertEqual(persistence.cutoffRecord(actorID: "human_b"), .missing)
        XCTAssertEqual(
            defaults.object(forKey: "test.chat.cutoff.human_a") as? Double,
            cutoff.timeIntervalSince1970
        )
    }

    func testUserDefaultsCutoffPreservesSubMillisecondVisibilityBoundary() {
        let suiteName = "ChatHistoryVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsChatHistoryCutoffPersistence(
            defaults: defaults,
            keyPrefix: "test.chat.precise"
        )
        let visibility = ChatHistoryVisibility(persistence: persistence)
        let cutoff = Date(timeIntervalSince1970: 100.123456)
        visibility.clear(actorID: "human_a", at: cutoff)

        XCTAssertFalse(
            visibility.isVisible(
                timestamp: Date(timeIntervalSince1970: 100.123455),
                actorID: "human_a"
            )
        )
        XCTAssertTrue(
            visibility.isVisible(
                timestamp: Date(timeIntervalSince1970: 100.123457),
                actorID: "human_a"
            )
        )
    }

    func testCorruptPersistedCutoffFailsClosedForOnlyThatActor() {
        let suiteName = "ChatHistoryVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("not-a-cutoff", forKey: "test.chat.corrupt.human_a")
        let persistence = UserDefaultsChatHistoryCutoffPersistence(
            defaults: defaults,
            keyPrefix: "test.chat.corrupt"
        )
        let visibility = ChatHistoryVisibility(persistence: persistence)

        XCTAssertFalse(
            visibility.isVisible(
                timestamp: Date(timeIntervalSince1970: 1_000),
                actorID: "human_a"
            )
        )
        XCTAssertTrue(
            visibility.isVisible(
                timestamp: Date(timeIntervalSince1970: 1),
                actorID: "human_b"
            )
        )
    }
}

private final class InMemoryChatCutoffPersistence: ChatHistoryCutoffPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Date] = [:]
    private(set) var savedActorIDs: [String] = []

    func cutoffRecord(actorID: String) -> ChatHistoryCutoffRecord {
        lock.withLock {
            values[actorID].map(ChatHistoryCutoffRecord.valid) ?? .missing
        }
    }

    func saveCutoff(_ date: Date, actorID: String) {
        lock.withLock {
            values[actorID] = date
            savedActorIDs.append(actorID)
        }
    }

    func cutoffDate(actorID: String) -> Date? {
        lock.withLock { values[actorID] }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
