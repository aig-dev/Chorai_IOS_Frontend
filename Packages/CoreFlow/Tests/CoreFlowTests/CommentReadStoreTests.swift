import Combine
import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class CommentReadStoreTests: XCTestCase {
    func testSessionInvalidationPublishesOnlyWhenClosingAnOpenRead() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        var publications = 0
        let subscription = store.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        XCTAssertEqual(publications, 0, "An idle store must not publish during initial session restoration")

        store.open("a")
        publications = 0
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        XCTAssertGreaterThan(publications, 0, "An open read must still notify its presentation when revoked")
        XCTAssertNil(store.cardID)
        let closingPublications = publications
        transport.finish(0, .page([row("late-private")], total: 1))
        XCTAssertTrue(store.comments.isEmpty)
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        XCTAssertEqual(publications, closingPublications)
    }

    func testReopenShowsThatCardsCachedThreadsBeforeTheNewResponse() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("root"), row("private", parent: "root")], total: 2))
        store.open("b")
        XCTAssertTrue(store.comments.isEmpty)
        transport.finish(1, .page([row("b-only")], total: 1))

        store.open("a")
        XCTAssertEqual(store.phase, .refreshing)
        XCTAssertEqual(store.comments.map(\.id), ["root"])
        XCTAssertEqual(store.comments.first?.replies.map(\.id), ["private"])
        XCTAssertEqual(transport.requests.map(\.cardID), ["a", "b", "a"])
        XCTAssertEqual(transport.requests.map(\.page), [1, 1, 1])

        transport.finish(2, .page([row("still-visible")], total: 1))
        XCTAssertEqual(store.comments.map(\.id), ["still-visible"])
        XCTAssertEqual(store.loadedCommentCount, 1)
    }

    func testTransientFailurePreservesPageAndAnEmptyPageCountsAsLoaded() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("known")], total: 1))
        store.open("a")
        transport.finish(1, .failed)
        XCTAssertEqual(store.comments.map(\.id), ["known"])
        XCTAssertEqual(store.phase, .failed(page: 1))

        store.retry()
        transport.finish(2, .page([], total: 0))
        store.open("a")
        XCTAssertEqual(store.phase, .refreshing, "An authorized empty page can be shown immediately")
        XCTAssertTrue(store.comments.isEmpty)
        transport.finish(3, .failed)
        XCTAssertTrue(store.hasFirstPage)
    }

    func testMismatchedCardRowsAreNeverPublishedOrCached() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("known", cardID: "a")], total: 1))
        store.open("a")
        transport.finish(1, .page([row("wrong", cardID: "b")], total: 1))
        XCTAssertEqual(store.comments.map(\.id), ["known"])
        XCTAssertEqual(store.phase, .failed(page: 1))
        XCTAssertNil(store.recordCreated(row("wrong-create", cardID: "b"), for: "a"))
        store.open("a")
        XCTAssertEqual(store.comments.map(\.id), ["known"])
    }

    func testFailedLoadMoreRetriesSamePageKeepingThreadContext() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("root")], total: 2))
        store.loadMore()
        transport.finish(1, .failed)
        XCTAssertEqual(store.comments.map(\.id), ["root"])
        XCTAssertFalse(store.canLoadMore)
        store.retry()
        XCTAssertEqual(transport.requests.map(\.page), [1, 2, 2])
        transport.finish(2, .page([row("reply", parent: "root")], total: 2))
        XCTAssertEqual(store.comments.first?.replies.map(\.id), ["reply"])
        XCTAssertFalse(store.canLoadMore)
    }

    func testPaginationRetainsOnlyPageOneForReopenAndIgnoresSupersededReads() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        let firstPage = (1...20).map { row(String($0)) }
        store.open("a")
        transport.finish(0, .page(firstPage, total: 42))
        store.loadMore()
        transport.finish(1, .page([row("21", parent: "1")], total: 42))
        XCTAssertEqual(store.comments.first?.replies.map(\.id), ["21"])
        store.loadMore()
        XCTAssertEqual(transport.requests.map(\.page), [1, 2, 3])

        store.open("b")
        store.open("a")
        XCTAssertEqual(store.loadedCommentCount, 20)
        XCTAssertTrue(store.comments[0].replies.isEmpty)
        transport.finish(2, .page([row("late-page")], total: 42))
        transport.finish(3, .page([row("other-card")], total: 1))
        XCTAssertEqual(store.loadedCommentCount, 20)
        XCTAssertEqual(store.phase, .refreshing)
        transport.finish(4, .page([row("fresh")], total: 1))
        XCTAssertEqual(store.comments.map(\.id), ["fresh"])
        XCTAssertFalse(store.canLoadMore)
    }

    func testDenialEvictsBothReadsAndDeletedCardsRejectOutstandingResults() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        let details = RecentCardReads<String>()
        details.insert("cached detail", for: "a")
        store.open("a")
        transport.finish(0, .page([row("private")], total: 1))
        store.open("a")
        transport.finish(1, .accessLost)
        XCTAssertNil(details.value(for: "a"))
        XCTAssertNil(store.cardID)
        XCTAssertTrue(store.comments.isEmpty)

        store.open("a")
        XCTAssertEqual(store.phase, .loading)
        NotificationCenter.default.post(name: .cardReadInvalidated, object: "a")
        transport.finish(2, .page([row("old-private")], total: 1))
        XCTAssertNil(store.cardID)
        XCTAssertTrue(store.comments.isEmpty)
    }

    func testCreateFinishingOnAnotherCardUpdatesOnlyTheSavedPage() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("parent")], total: 1))
        store.open("b")
        transport.finish(1, .page([row("other")], total: 1))
        XCTAssertEqual(store.recordCreated(row("reply", parent: "parent"), for: "a"), 2)
        XCTAssertEqual(store.comments.map(\.id), ["other"])
        store.open("a")
        XCTAssertEqual(store.comments.first?.replies.map(\.id), ["reply"])

        NotificationCenter.default.post(name: .cardReadInvalidated, object: "a")
        XCTAssertNil(store.recordCreated(row("late"), for: "a"))
        store.open("a")
        XCTAssertEqual(store.phase, .loading)
        XCTAssertTrue(store.comments.isEmpty)
    }

    func testSessionChangeDropsPrivatePagesAndSignedOutReadsNeverStart() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("private")], total: 1))
        store.open("a")
        transport.session = nil
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        XCTAssertNil(store.comment(withID: "private"))
        XCTAssertNil(store.cardID)
        XCTAssertTrue(store.comments.isEmpty)
        store.open("a")
        XCTAssertEqual(transport.requests.count, 2)

        transport.session = 2
        store.open("a")
        transport.finish(1, .page([row("previous-account")], total: 1))
        XCTAssertTrue(store.comments.isEmpty)
        XCTAssertEqual(store.phase, .loading)
        transport.finish(2, .page([row("new-account")], total: 1))
        XCTAssertEqual(store.comments.map(\.id), ["new-account"])
    }

    func testConfirmedCreateAndThreadRemovalCannotBeUndoneByAnOlderRead() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        store.open("a")
        transport.finish(0, .page([row("root")], total: 1))
        store.refresh()
        XCTAssertEqual(store.recordCreated(row("reply", parent: "root"), for: "a"), 2)
        transport.finish(1, .page([row("root")], total: 1))
        XCTAssertEqual(store.comments.first?.replies.map(\.id), ["reply"])
        store.open("a")
        XCTAssertEqual(store.comments.first?.replies.map(\.id), ["reply"])

        let pending = transport.requests.count - 1
        XCTAssertEqual(store.removeThread("root", for: "a"), 0)
        transport.finish(pending, .page([row("root"), row("reply", parent: "root")], total: 2))
        XCTAssertTrue(store.comments.isEmpty)
        store.open("a")
        XCTAssertTrue(store.comments.isEmpty)
        XCTAssertEqual(store.phase, .refreshing)
    }

    func testRemovingAThreadDuringReopenKeepsTheNextPageReachable() async {
        let transport = CommentReader()
        let store = transport.makeStore()
        let firstPage = (1...20).map { row(String($0)) }
        store.open("a")
        transport.finish(0, .page(firstPage, total: 22))
        store.open("a")
        XCTAssertEqual(store.removeThread("1", for: "a"), 21)
        transport.finish(1, .page(firstPage, total: 22))
        XCTAssertNil(store.comment(withID: "1"))
        store.loadMore()
        XCTAssertEqual(transport.requests.map(\.page), [1, 1, 2])
    }

    private func row(_ id: String, parent: String? = nil, cardID: String? = nil) -> CommentModel {
        CommentModel(
            id: id, cardId: cardID, parentCommentId: parent, visibility: .privateComment, content: id,
            createdAt: "2026-11-13T00:00:00Z", updatedAt: nil,
            user: CommentUser(id: "author", username: "Author", avatarUrl: nil), replies: []
        )
    }
}

@MainActor
private final class CommentReader {
    var session: UInt64? = 1
    struct Request {
        let cardID: String
        let page: Int
        let finish: (CommentPageResult) -> Void
    }
    var requests: [Request] = []

    func makeStore() -> CommentReadStore {
        CommentReadStore(session: { self.session }) { cardID, page, _, completion in
            self.requests.append(.init(cardID: cardID, page: page, finish: completion))
        }
    }

    func finish(_ index: Int, _ result: CommentPageResult) {
        requests[index].finish(result)
    }
}
