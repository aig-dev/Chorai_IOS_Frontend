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
    func testCollectAndAdvanceOnlyMovesAfterSuccessAndCanUndoFromHistory() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(())]
        service.unfavoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.collectAndAdvanceCurrent()
        XCTAssertEqual(store.currentCard?.id, "a", "Do not advance while the service is pending")
        await settle()
        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertEqual(store.undoCollectionCardID, "a")
        XCTAssertEqual(store.browsingCards.first?.isFavorited, true)
        store.undoLastCollection()
        await settle()
        XCTAssertEqual(store.currentCard?.id, "b", "Undo restores collection, not browsing position")
        XCTAssertEqual(store.browsingCards.first?.isFavorited, false)
        XCTAssertNil(store.undoCollectionCardID)
    }

    @MainActor
    func testFailedSwipeCollectionStaysOnCardAndCanRetry() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.failure(.offline), .success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.collectAndAdvanceCurrent()
        await settle()
        XCTAssertEqual(store.currentCard?.id, "a")
        XCTAssertEqual(store.currentCard?.isFavorited, false)
        XCTAssertEqual(store.notice, .favoriteFailed)
        XCTAssertNil(store.undoCollectionCardID)
        store.collectAndAdvanceCurrent()
        await settle()
        XCTAssertEqual(store.currentCard?.id, "b")
    }

    @MainActor
    func testDismissingCollectionUndoKeepsConfirmedCollectionAndBrowsingPosition() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.collectAndAdvanceCurrent()
        await settle()

        store.dismissCollectionUndo(for: "a")

        XCTAssertNil(store.undoCollectionCardID)
        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertEqual(store.history.map(\.id), ["a"])
        XCTAssertEqual(store.history.first?.isFavorited, true)
        XCTAssertEqual(service.favoritedAssetIDs, ["a"])
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty, "Dismissing feedback must not undo the confirmed collection")
    }

    @MainActor
    func testExpiredCollectionFeedbackCannotDismissANewerCardsUndo() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b"), card("c")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(()), .success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.collectAndAdvanceCurrent()
        await settle()
        store.collectAndAdvanceCurrent()
        await settle()

        store.dismissCollectionUndo(for: "a")
        XCTAssertEqual(store.undoCollectionCardID, "b")
        XCTAssertEqual(store.currentCard?.id, "c")

        store.dismissCollectionUndo(for: "b")
        XCTAssertNil(store.undoCollectionCardID)
        XCTAssertEqual(store.history.map(\.id), ["a", "b"])
        XCTAssertTrue(store.history.allSatisfy(\.isFavorited))
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty)
    }

    @MainActor
    func testCollectionFeedbackExpiryDuringPendingUndoPreservesFailedUndoRetry() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(())]
        service.unfavoriteResults = [.failure(.offline), .success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.collectAndAdvanceCurrent()
        await settle()

        store.undoLastCollection()
        XCTAssertTrue(store.isInteractionLocked)
        store.dismissCollectionUndo(for: "a")
        await settle()
        XCTAssertEqual(store.undoCollectionCardID, "a")
        XCTAssertEqual(store.history.first?.isFavorited, true)
        XCTAssertEqual(store.notice, .favoriteFailed)

        store.undoLastCollection()
        await settle()
        XCTAssertNil(store.undoCollectionCardID)
        XCTAssertEqual(store.history.first?.isFavorited, false)
        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertEqual(service.unfavoritedAssetIDs, ["a", "a"])
    }

    @MainActor
    func testRevisitingCollectedCardNeverUncollectsOnRightSwipe() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a", isFavorited: true), card("b")], nextRefreshToken: nil))]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.dismissCurrent()
        store.previous()
        store.collectAndAdvanceCurrent()
        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertEqual(store.browsingCards.first?.isFavorited, true)
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty)
        XCTAssertTrue(service.favoritedAssetIDs.isEmpty)
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
        XCTAssertTrue(store.isInteractionLocked)
        store.applyFavoriteState(.init(cardID: "a", isFavorited: true, favoriteCount: 7))
        await settle()

        XCTAssertEqual(store.currentCard?.isFavorited, true)
        XCTAssertEqual(store.currentCard?.favoriteCount, 7)
        XCTAssertFalse(store.isInteractionLocked)
        XCTAssertEqual(store.notice, .favoriteFailed)
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

    @MainActor
    func testFailedUndoKeepsCollectionAndUndoAvailable() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [.success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))]
        service.favoriteResults = [.success(())]
        service.unfavoriteResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.collectAndAdvanceCurrent()
        await settle()
        store.undoLastCollection()
        await settle()
        XCTAssertEqual(store.browsingCards.first?.isFavorited, true)
        XCTAssertEqual(store.undoCollectionCardID, "a")
        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertEqual(store.notice, .favoriteFailed)
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
