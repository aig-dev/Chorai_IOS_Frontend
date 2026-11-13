import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class CardLikeStoreTests: XCTestCase {
    func testLikeIsVisibleImmediatelyAndPublishesOnlyAfterSuccess() async {
        let service = ScriptedCardLikeService([
            .init(delay: 50_000_000, result: .success(()))
        ])
        var published: [CardLikeState] = []
        let store = CardLikeStore(
            state: .init(cardID: "ast_1", isLiked: false, likeCount: 4),
            service: service,
            onCommit: { published.append($0) }
        )

        store.toggle()

        XCTAssertEqual(
            store.state,
            .init(cardID: "ast_1", isLiked: true, likeCount: 5)
        )
        XCTAssertTrue(published.isEmpty)
        await waitUntil { store.phase == .ready && store.state.isLiked }
        XCTAssertEqual(store.state.likeCount, 5)
        XCTAssertEqual(published, [store.state])
    }

    func testUnlikeFailureKeepsCommittedStateAndRapidTapSendsOneRequest() async {
        let service = ScriptedCardLikeService([
            .init(
                delay: 50_000_000,
                result: .failure(.transport(code: "offline"))
            )
        ])
        let store = CardLikeStore(
            state: .init(cardID: "ast_1", isLiked: true, likeCount: 1),
            service: service
        )

        store.toggle()
        XCTAssertEqual(store.state, .init(cardID: "ast_1", isLiked: false, likeCount: 0))
        store.toggle()

        await waitUntil {
            store.phase == .failed(.transport(code: "offline"))
        }
        XCTAssertEqual(
            store.state,
            .init(cardID: "ast_1", isLiked: true, likeCount: 1)
        )
        let requests = await service.requests()
        XCTAssertEqual(
            requests,
            [.init(cardID: "ast_1", liked: false)]
        )
    }

    func testRetryCommitsExactlyOnceAndNeverMakesCountNegative() async {
        let service = ScriptedCardLikeService([
            .init(delay: 0, result: .failure(.transport(code: "offline"))),
            .init(delay: 0, result: .success(()))
        ])
        var published: [CardLikeState] = []
        let store = CardLikeStore(
            state: .init(cardID: "ast_1", isLiked: true, likeCount: 0),
            service: service,
            onCommit: { published.append($0) }
        )

        store.toggle()
        await waitUntil {
            if case .failed = store.phase { return true }
            return false
        }
        store.toggle()
        await waitUntil { store.phase == .ready && !store.state.isLiked }

        XCTAssertEqual(store.state.likeCount, 0)
        XCTAssertEqual(published, [store.state])
        let requests = await service.requests()
        XCTAssertEqual(requests.count, 2)
    }

    func testFailedLikeRollsBackToAConcurrentConfirmedReceipt() async {
        let service = ScriptedCardLikeService([.init(delay: 0, result: .failure(.transport(code: "offline")))])
        var published: [CardLikeState] = []
        let store = CardLikeStore(state: .init(cardID: "a", isLiked: false, likeCount: 2),
                                  service: service, onCommit: { published.append($0) })
        store.toggle()
        store.applyCommitted(.init(cardID: "a", isLiked: false, likeCount: 8))
        XCTAssertEqual(store.state, .init(cardID: "a", isLiked: true, likeCount: 9))
        await waitUntil { store.phase == .failed(.transport(code: "offline")) }
        XCTAssertEqual(store.state, .init(cardID: "a", isLiked: false, likeCount: 8))
        XCTAssertTrue(published.isEmpty)
    }

    func testSameCardHydrationCannotCancelLikeOrReplaceNewerReceipt() async {
        let service = ScriptedCardLikeService([.init(delay: 0, result: .success(()))])
        var published: [CardLikeState] = []
        let store = CardLikeStore(state: .init(cardID: "a", isLiked: false, likeCount: 2),
                                  service: service, onCommit: { published.append($0) })
        store.toggle()
        store.applyCommitted(.init(cardID: "a", isLiked: true, likeCount: 9))
        store.hydrate(.init(cardID: "a", isLiked: false, likeCount: 2))
        XCTAssertTrue(store.isMutating)
        XCTAssertEqual(store.state, .init(cardID: "a", isLiked: true, likeCount: 9))
        await waitUntil { store.phase == .ready }
        XCTAssertEqual(published, [.init(cardID: "a", isLiked: true, likeCount: 9)])
    }

    func testSwipingToAnotherCardKeepsTheOriginalWriteAndItsReceipt() async {
        let service = ScriptedCardLikeService([
            .init(delay: 40_000_000, result: .success(())),
            .init(delay: 0, result: .success(()))
        ])
        var published: [CardLikeState] = []
        let store = CardLikeStore(state: .init(cardID: "a", isLiked: false, likeCount: 3),
                                  service: service, onCommit: { published.append($0) })
        store.toggle()
        store.hydrate(.init(cardID: "b", isLiked: false, likeCount: 7))
        XCTAssertEqual(store.state, .init(cardID: "b", isLiked: false, likeCount: 7))
        XCTAssertFalse(store.isMutating)
        store.toggle()
        await waitUntil { published.count == 2 }
        XCTAssertEqual(store.state, .init(cardID: "b", isLiked: true, likeCount: 8))
        XCTAssertEqual(published.first(where: { $0.cardID == "a" }), .init(cardID: "a", isLiked: true, likeCount: 4))
        XCTAssertEqual(store.phase, .ready)
    }

    func testRevisitingAPendingLikeUsesOriginalBaselineAndPreventsDuplicateRequest() async {
        let service = ScriptedCardLikeService([.init(delay: 0, result: .success(()))])
        var published: [CardLikeState] = []
        let store = CardLikeStore(state: .init(cardID: "a", isLiked: false, likeCount: 3),
                                  service: service, onCommit: { published.append($0) })
        store.toggle()
        store.hydrate(.init(cardID: "b", isLiked: true, likeCount: 6))
        store.applyCommitted(.init(cardID: "a", isLiked: false, likeCount: 5))
        store.hydrate(.init(cardID: "a", isLiked: false, likeCount: 3))
        XCTAssertTrue(store.isMutating)
        XCTAssertEqual(store.state, .init(cardID: "a", isLiked: true, likeCount: 6))
        store.toggle()
        await waitUntil { store.phase == .ready }
        XCTAssertEqual(published, [.init(cardID: "a", isLiked: true, likeCount: 6)])
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(predicate())
    }
}

private actor ScriptedCardLikeService: CoreCardLikeServing {
    struct Script: Sendable {
        let delay: UInt64
        let result: Result<Void, CardLikeError>
    }

    struct Request: Equatable, Sendable {
        let cardID: String
        let liked: Bool
    }

    private var scripts: [Script]
    private var recorded: [Request] = []

    init(_ scripts: [Script]) {
        self.scripts = scripts
    }

    func setLiked(cardID: String, liked: Bool) async throws {
        recorded.append(.init(cardID: cardID, liked: liked))
        let script = scripts.removeFirst()
        if script.delay > 0 {
            try await Task.sleep(nanoseconds: script.delay)
        }
        try script.result.get()
    }

    func requests() -> [Request] {
        recorded
    }
}
