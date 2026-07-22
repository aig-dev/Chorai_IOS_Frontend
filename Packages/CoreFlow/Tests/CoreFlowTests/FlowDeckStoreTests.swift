import Foundation
import XCTest
@testable import CoreFlow

final class FlowDeckStoreTests: XCTestCase {
    @MainActor
    func testInitialLoadDeduplicatesCards() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(
                    cards: [card("a"), card("a"), card("b")],
                    nextRefreshToken: nil
                )
            )
        ]
        let store = FlowDeckStore(service: service)

        store.loadInitialIfNeeded()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["a", "b"])
        XCTAssertEqual(store.phase, .loaded)
    }

    @MainActor
    func testEmptyPageWithNextTokenContinuesUntilFirstCard() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(cards: [], nextRefreshToken: "next-page")
            ),
            .success(
                FlowPage(cards: [card("a")], nextRefreshToken: nil)
            )
        ]
        let store = FlowDeckStore(service: service)

        store.loadInitialIfNeeded()
        await settle()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["a"])
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(
            service.requestedRefreshTokens,
            [nil, "next-page"]
        )
    }

    @MainActor
    func testDismissPrefetchesWithCanonicalTokenAndDeduplicates() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(
                    cards: [card("a"), card("b"), card("c")],
                    nextRefreshToken: "next"
                )
            ),
            .success(
                FlowPage(
                    cards: [card("c"), card("d")],
                    nextRefreshToken: nil
                )
            )
        ]
        let store = FlowDeckStore(service: service)

        store.loadInitialIfNeeded()
        await settle()
        store.dismissCurrent()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["b", "c", "d"])
        XCTAssertEqual(service.requestedRefreshTokens.compactMap { $0 }, ["next"])
    }

    @MainActor
    func testInitialFailureExposesRetryableState() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)

        store.loadInitialIfNeeded()
        await settle()

        XCTAssertEqual(store.phase, .failed("Couldn't load your flow."))
    }

    @MainActor
    func testRetryAfterInitialFailureResetsAndLoads() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .failure(.offline),
            .success(FlowPage(cards: [card("retry")], nextRefreshToken: nil))
        ]
        let store = FlowDeckStore(service: service)

        store.loadInitialIfNeeded()
        await settle()
        store.refresh()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["retry"])
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(service.requestedRefreshTokens.count, 2)
    }

    @MainActor
    func testFavoriteToggleActivatesCurrentCardWithoutAdvancingDeck() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        var succeededAssetID: String?

        store.toggleFavoriteCurrent { succeededAssetID = $0 }
        await settle()

        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertEqual(store.currentCard?.isFavorited, true)
        XCTAssertEqual(store.currentCard?.favoriteCount, 1)
        XCTAssertEqual(service.favoritedAssetIDs, ["a"])
        XCTAssertEqual(succeededAssetID, "a")
        XCTAssertNil(store.notice)
    }

    @MainActor
    func testFavoriteToggleCanDeactivateCurrentCardWithoutAdvancingDeck() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(
                    cards: [card("a", isFavorited: true), card("b")],
                    nextRefreshToken: nil
                )
            )
        ]
        service.unfavoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        var succeededAssetID: String?

        store.toggleFavoriteCurrent { succeededAssetID = $0 }
        await settle()

        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertEqual(store.currentCard?.isFavorited, false)
        XCTAssertEqual(store.currentCard?.favoriteCount, 0)
        XCTAssertEqual(service.unfavoritedAssetIDs, ["a"])
        XCTAssertNil(succeededAssetID)
        XCTAssertNil(store.notice)
    }

    @MainActor
    func testFavoriteToggleFailureRestoresCurrentCardState() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        var succeededAssetID: String?

        store.toggleFavoriteCurrent { succeededAssetID = $0 }
        await settle()

        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertEqual(store.currentCard?.isFavorited, false)
        XCTAssertEqual(store.currentCard?.favoriteCount, 0)
        XCTAssertEqual(store.notice, .favoriteFailed)
        XCTAssertNil(succeededAssetID)
    }

    @MainActor
    func testOwnedCardCannotBeFavorited() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("owned", isOwner: true)], nextRefreshToken: nil))
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        let original = store.currentCard

        store.toggleFavoriteCurrent()
        await settle()

        XCTAssertEqual(store.currentCard, original)
        XCTAssertTrue(service.favoritedAssetIDs.isEmpty)
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty)
        XCTAssertFalse(store.isInteractionLocked)
        XCTAssertNil(store.notice)
    }

    @MainActor
    func testApplyLikeStateUpdatesMatchingCardWithoutAdvancingDeck() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(
                    cards: [card("a"), card("b")],
                    nextRefreshToken: nil
                )
            )
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        let ids = store.cards.map(\.id)
        let favorite = store.currentCard?.isFavorited
        let favoriteCount = store.currentCard?.favoriteCount

        store.applyLikeState(
            .init(cardID: "a", isLiked: true, likeCount: 9)
        )

        XCTAssertEqual(store.cards.map(\.id), ids)
        XCTAssertEqual(store.currentCard?.isLiked, true)
        XCTAssertEqual(store.currentCard?.likeCount, 9)
        XCTAssertEqual(store.currentCard?.isFavorited, favorite)
        XCTAssertEqual(store.currentCard?.favoriteCount, favoriteCount)
    }

    @MainActor
    func testApplyLikeStateIgnoresUnknownCard() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(cards: [card("a")], nextRefreshToken: nil)
            )
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        let before = store.cards

        store.applyLikeState(
            .init(cardID: "missing", isLiked: true, likeCount: 1)
        )

        XCTAssertEqual(store.cards, before)
    }

    private func card(
        _ id: String,
        isFavorited: Bool = false,
        isOwner: Bool = false
    ) -> FlowCard {
        FlowCard(
            id: id,
            title: "Title \(id)",
            content: "Body \(id)",
            contentHash: nil,
            tags: ["tag"],
            isPublic: true,
            createdAt: "2026-07-10T00:00:00Z",
            updatedAt: "2026-07-10T00:00:00Z",
            favoriteCount: isFavorited ? 1 : 0,
            likeCount: 0,
            commentCount: 0,
            rate: 0,
            isFavorited: isFavorited,
            isLiked: false,
            isPinned: false,
            pinnedAt: nil,
            author: FlowAuthor(id: "act_1", username: "Ada", avatarURL: nil),
            isOwner: isOwner
        )
    }

    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
