import Combine
import Foundation
import XCTest
@testable import CoreFlow

final class FlowDeckStoreTests: XCTestCase {
    @MainActor
    func testHistorySelectionPreservesUnreadFrontierAndRejectsInvalidIndex() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b"), card("c")], nextRefreshToken: nil))]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.dismissCurrent()
        store.dismissCurrent()
        store.revisitHistory(at: 0)
        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertEqual(store.cards.map(\.id), ["c"])
        store.revisitHistory(at: -1)
        XCTAssertEqual(store.currentCard?.id, "a")
        store.revisitHistory(at: 2)
        XCTAssertEqual(store.currentCard?.id, "a")
        store.resumeExploring()
        XCTAssertEqual(store.currentCard?.id, "c")
        XCTAssertEqual(store.history.map(\.id), ["a", "b"])
        XCTAssertEqual(service.requestedRefreshTokens.count, 1)
    }

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
    func testRevokedCardIsRemovedFromHistoryAndAnOlderPageCannotRestoreIt() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(.init(cards: [card("gone"), card("keep")], nextRefreshToken: "next")),
            .success(.init(cards: [card("gone"), card("next")], nextRefreshToken: nil))
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.dismissCurrent()
        NotificationCenter.default.post(name: .cardReadInvalidated, object: "gone")
        await settle()

        XCTAssertEqual(store.browsingCards.map(\.id), ["keep", "next"])
        XCTAssertEqual(store.currentCard?.id, "keep")
        XCTAssertTrue(store.history.isEmpty)
    }

    @MainActor
    func testReadSessionChangeDiscardsQueuedPageBeforeReload() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(.init(cards: [card("old")], nextRefreshToken: nil)),
            .success(.init(cards: [card("new")], nextRefreshToken: nil))
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        await settle()
        XCTAssertTrue(store.browsingCards.isEmpty)
        XCTAssertEqual(store.phase, .idle)
        store.loadInitialIfNeeded()
        await settle()
        XCTAssertEqual(store.cards.map(\.id), ["new"])
    }

    @MainActor
    func testRevokingLastCardLoadsNextPage() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(.init(cards: [card("gone")], nextRefreshToken: "next")),
            .success(.init(cards: [card("next-card")], nextRefreshToken: nil))
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        NotificationCenter.default.post(name: .cardReadInvalidated, object: "gone")
        await settle()
        XCTAssertEqual(store.currentCard?.id, "next-card")
        XCTAssertEqual(service.requestedRefreshTokens, [nil, "next"])
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
        XCTAssertTrue(store.failedFavoriteIDs.isEmpty)
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
        XCTAssertTrue(store.failedFavoriteIDs.isEmpty)
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
        XCTAssertEqual(store.failedFavoriteIDs, ["a"])
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
        XCTAssertFalse(store.isFavoritePending("owned"))
        XCTAssertTrue(store.failedFavoriteIDs.isEmpty)
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

    @MainActor
    func testPreviousAndResumeKeepHistoryWithoutChangingCollection() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b"), card("c")], nextRefreshToken: nil))]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.dismissCurrent()
        store.dismissCurrent()
        store.previous()
        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertTrue(store.isRevisiting)
        store.previous()
        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertFalse(store.canGoBack)
        store.resumeExploring()
        XCTAssertEqual(store.currentCard?.id, "c")
        XCTAssertEqual(store.browsingCards.map(\.id), ["a", "b", "c"])
        XCTAssertTrue(service.favoritedAssetIDs.isEmpty)
    }

    @MainActor
    func testBrowsingThroughSavedLikedAndOwnedCardsOnlyMovesTheDeck() async {
        let service = MockCoreFlowService()
        let saved = card("saved", isFavorited: true).replacingLike(with: .init(cardID: "saved", isLiked: true, likeCount: 4))
        let originals = [card("new"), saved, card("mine", isOwner: true)]
        service.recommendedResults = [.success(FlowPage(cards: originals, nextRefreshToken: nil))]
        var receipts: [CardFavoriteState] = []
        let store = FlowDeckStore(service: service, onFavoriteCommitted: { receipts.append($0) })
        store.loadInitialIfNeeded()
        await settle()

        for expected in originals {
            XCTAssertEqual(store.currentCard, expected)
            store.dismissCurrent()
        }
        XCTAssertEqual(store.phase, .empty)
        XCTAssertEqual(store.history, originals)
        store.previous()
        store.revisitHistory(at: 1)
        store.dismissCurrent()
        XCTAssertEqual(store.currentCard?.id, "mine")
        XCTAssertEqual(store.history, originals)
        XCTAssertTrue(service.favoritedAssetIDs.isEmpty)
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty)
        XCTAssertTrue(receipts.isEmpty)
    }

    @MainActor
    func testBrowsingWhileBookmarkButtonIsPendingOnlySendsTheOriginalWrite() async {
        let service = MockCoreFlowService()
        let receipt = PassthroughSubject<Void, CoreFlowError>()
        service.delayedFavorites["a"] = receipt
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b"), card("c")], nextRefreshToken: nil))]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.toggleFavoriteCurrent()
        store.dismissCurrent()
        store.dismissCurrent()
        XCTAssertEqual(store.currentCard?.id, "c")
        receipt.send(completion: .failure(.offline))
        await settle()
        XCTAssertEqual(store.history.first?.isFavorited, false)
        XCTAssertEqual(store.failedFavoriteIDs, ["a"])
        XCTAssertEqual(store.currentCard?.id, "c")
        XCTAssertEqual(service.favoritedAssetIDs, ["a"])
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty)
    }

    @MainActor
    func testGridFavoriteMutatesRequestedCardWithoutMovingDeck() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.toggleFavorite(assetID: "b")
        await settle()
        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertEqual(store.browsingCards.last?.isFavorited, true)
        XCTAssertEqual(service.favoritedAssetIDs, ["b"])
    }

    @MainActor
    func testDetailFavoriteCommitUpdatesHistoryAndMissingCountPreservesDirection() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.dismissCurrent()
        store.applyFavoriteState(.init(cardID: "a", isFavorited: true, favoriteCount: nil))
        store.applyFavoriteState(.init(cardID: "a", isFavorited: true, favoriteCount: nil))
        store.previous()
        XCTAssertEqual(store.currentCard?.isFavorited, true)
        XCTAssertEqual(store.currentCard?.favoriteCount, 1, "Repeated broadcasts must not increment twice")
        store.applyFavoriteState(.init(cardID: "a", isFavorited: false, favoriteCount: 20))
        XCTAssertEqual(store.currentCard?.favoriteCount, 20)
        XCTAssertEqual(store.currentCard?.isFavorited, false)
    }

    @MainActor
    func testFavoriteFailureDoesNotEraseConcurrentLikeCommit() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a")], nextRefreshToken: nil))]
        service.favoriteResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.toggleFavoriteCurrent()
        store.applyLikeState(.init(cardID: "a", isLiked: true, likeCount: 14))
        await settle()
        XCTAssertEqual(store.currentCard?.isFavorited, false)
        XCTAssertEqual(store.currentCard?.isLiked, true)
        XCTAssertEqual(store.currentCard?.likeCount, 14)
    }

    @MainActor
    func testFavoriteFailurePreservesNewerCommittedFavoriteFromAnotherSurface() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a")], nextRefreshToken: nil))]
        service.favoriteResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.toggleFavoriteCurrent()
        XCTAssertTrue(store.isFavoritePending("a"))
        store.applyFavoriteState(.init(cardID: "a", isFavorited: true, favoriteCount: 7))
        await settle()

        XCTAssertEqual(store.currentCard?.isFavorited, true)
        XCTAssertEqual(store.currentCard?.favoriteCount, 7)
        XCTAssertFalse(store.isFavoritePending("a"))
        XCTAssertTrue(store.failedFavoriteIDs.isEmpty, "The newer receipt already confirmed this bookmark")
    }

    @MainActor
    func testOtherCardFavoriteCommitDoesNotPreventFailedMutationRollback() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.toggleFavoriteCurrent()
        store.applyFavoriteState(.init(cardID: "b", isFavorited: true, favoriteCount: 7))
        await settle()

        XCTAssertEqual(store.currentCard?.isFavorited, false)
        XCTAssertEqual(store.currentCard?.favoriteCount, 0)
        XCTAssertEqual(store.browsingCards.last?.isFavorited, true)
        XCTAssertEqual(store.browsingCards.last?.favoriteCount, 7)
    }

    @MainActor
    func testFavoriteSuccessKeepsNewerCommittedCountAndBroadcastsIt() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(())]
        var committed: CardFavoriteState?
        let store = FlowDeckStore(service: service, onFavoriteCommitted: { committed = $0 })
        store.loadInitialIfNeeded()
        await settle()

        store.toggleFavoriteCurrent()
        store.applyFavoriteState(.init(cardID: "a", isFavorited: true, favoriteCount: 7))
        await settle()

        XCTAssertEqual(store.currentCard?.favoriteCount, 7)
        XCTAssertEqual(committed, .init(cardID: "a", isFavorited: true, favoriteCount: 7))
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

    @MainActor
    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
