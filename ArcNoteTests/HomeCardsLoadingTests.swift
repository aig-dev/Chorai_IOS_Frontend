import XCTest
import Combine
@testable import ArcNote

@MainActor
final class HomeCardsLoadingTests: XCTestCase {
    func testSameProfilePageSharesFetchAndAdvancesExactlyOnce() async {
        let feed = ProfileFeedProbe()
        let manager = HomeCardsManager(readSession: { 1 }, fetchPublicCards: { actor, page, perPage in feed.fetch(actor, page, perPage) })
        manager.loadPublicProfileCards(actorId: "alice", refresh: true)
        manager.loadPublicProfileCards(actorId: "alice", refresh: true)
        manager.loadPublicProfileCards(actorId: "alice")
        XCTAssertEqual(feed.pages, [1])
        feed.complete(0, count: 20)
        await flush()
        XCTAssertEqual(manager.cards.count, 20)
        manager.loadMoreCards()
        manager.loadPublicProfileCards(actorId: "alice")
        XCTAssertEqual(feed.pages, [1, 2])
        feed.complete(1, count: 3)
        await flush()
        XCTAssertEqual(manager.cards.count, 23)
        XCTAssertFalse(manager.hasMoreData)
        manager.loadPublicProfileCards(actorId: "alice")
        XCTAssertEqual(feed.pages, [1, 2])
    }

    func testProfileSwitchAndSessionChangeRejectOldPage() async {
        let feed = ProfileFeedProbe()
        let manager = HomeCardsManager(readSession: { feed.session }, fetchPublicCards: { actor, page, perPage in feed.fetch(actor, page, perPage) })
        manager.loadPublicProfileCards(actorId: "alice", refresh: true)
        manager.loadPublicProfileCards(actorId: "bob", refresh: true)
        feed.complete(0, count: 20)
        feed.complete(1, count: 1)
        await flush()
        XCTAssertEqual(manager.cards.map(\.content), ["bob"])
        manager.loadPublicProfileCards(actorId: "bob", refresh: true)
        feed.session = 2
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        feed.complete(2, count: 1)
        await flush()
        XCTAssertTrue(manager.cards.isEmpty)
        manager.loadPublicProfileCards(actorId: "bob", refresh: true)
        XCTAssertEqual(feed.pages, [1, 1, 1, 1])
        feed.complete(3, count: 1)
        await flush()
        XCTAssertEqual(manager.cards.count, 1)
    }

    func testRefreshSupersedesPaginationAndFailureCanRetry() async {
        let feed = ProfileFeedProbe()
        let manager = HomeCardsManager(readSession: { 1 }, fetchPublicCards: { actor, page, perPage in feed.fetch(actor, page, perPage) })
        manager.loadPublicProfileCards(actorId: "alice", refresh: true)
        feed.complete(0, count: 20)
        await flush()
        manager.loadMoreCards()
        manager.loadPublicProfileCards(actorId: "alice", refresh: true)
        XCTAssertEqual(feed.pages, [1, 2, 1])
        feed.complete(1, count: 20)
        feed.subjects[2].send(completion: .failure(.noData))
        await flush()
        XCTAssertTrue(manager.cards.isEmpty)
        XCTAssertFalse(manager.isLoading)
        manager.loadPublicProfileCards(actorId: "alice")
        XCTAssertEqual(feed.pages, [1, 2, 1, 1])
        feed.complete(3, count: 2)
        await flush()
        XCTAssertEqual(manager.cards.count, 2)
    }

    private func flush() async { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
}

@MainActor
private final class ProfileFeedProbe {
    var session: UInt64? = 1
    var pages: [Int] = []
    var actors: [String] = []
    var subjects: [PassthroughSubject<UserCardsListResponse, NetworkError>] = []
    func fetch(_ actor: String, _ page: Int, _ perPage: Int) -> AnyPublisher<UserCardsListResponse, NetworkError> {
        XCTAssertEqual(perPage, 20)
        pages.append(page); actors.append(actor)
        let subject = PassthroughSubject<UserCardsListResponse, NetworkError>()
        subjects.append(subject)
        return subject.eraseToAnyPublisher()
    }
    func complete(_ index: Int, count: Int) {
        let cards = (0..<count).map { item in
            UserCard(id: "\(actors[index])-\(pages[index])-\(item)", title: nil, content: actors[index], contentHash: "hash",
                     isPublic: true, tags: [], createdAt: "", updatedAt: "", likeCount: 0, commentCount: nil, isLiked: false,
                     isPinned: false, pinnedAt: nil, isFavorited: nil, favoriteCount: nil, rate: 0)
        }
        subjects[index].send(.init(success: true, message: nil, data: cards, meta: nil))
        subjects[index].send(completion: .finished)
    }
}
