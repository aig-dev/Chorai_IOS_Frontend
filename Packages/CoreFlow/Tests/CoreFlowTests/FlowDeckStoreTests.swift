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
    func testSaveAdvancesAndOffersUndo() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.saveCurrent()
        await settle()

        XCTAssertEqual(store.currentCard?.id, "b")
        XCTAssertEqual(store.undoAssetID, "a")
        XCTAssertEqual(store.notice, .saved(assetID: "a"))
        XCTAssertEqual(service.favoritedAssetIDs, ["a"])
    }

    @MainActor
    func testSaveFailureRestoresExactCard() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.failure(.offline)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.saveCurrent()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["a", "b"])
        XCTAssertEqual(store.cards.first, card("a"))
        XCTAssertEqual(store.notice, .saveFailed)
        XCTAssertNil(store.undoAssetID)
    }

    @MainActor
    func testUndoRestoresCardAndUnfavorites() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.success(())]
        service.unfavoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.saveCurrent()
        await settle()

        store.undoLastSave()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["a", "b"])
        XCTAssertNil(store.undoAssetID)
        XCTAssertEqual(service.unfavoritedAssetIDs, ["a"])
    }

    @MainActor
    func testUndoFailureRemovesOptimisticRestoreAndOffersRetryNotice() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.success(())]
        service.unfavoriteResults = [.failure(.server)]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.saveCurrent()
        await settle()

        store.undoLastSave()
        await settle()

        XCTAssertEqual(store.cards.map(\.id), ["b"])
        XCTAssertEqual(store.undoAssetID, "a")
        XCTAssertEqual(store.notice, .undoFailed)
    }

    @MainActor
    func testSaveLocksDuplicateRequestsUntilCompletion() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.saveCurrent()
        store.saveCurrent()

        XCTAssertEqual(service.favoritedAssetIDs, ["a"])
    }

    @MainActor
    func testAlreadyFavoritedCardNeverCreatesOrRemovesPriorFavorite() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(
                FlowPage(
                    cards: [card("a", isFavorited: true), card("b")],
                    nextRefreshToken: nil
                )
            )
        ]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()

        store.saveCurrent()
        store.undoLastSave()

        XCTAssertEqual(store.cards.map(\.id), ["a", "b"])
        XCTAssertTrue(service.favoritedAssetIDs.isEmpty)
        XCTAssertTrue(service.unfavoritedAssetIDs.isEmpty)
    }

    @MainActor
    func testExpireUndoOnlyClearsMatchingSave() async {
        let service = MockCoreFlowService()
        service.recommendedResults = [
            .success(FlowPage(cards: [card("a"), card("b")], nextRefreshToken: nil))
        ]
        service.favoriteResults = [.success(())]
        let store = FlowDeckStore(service: service)
        store.loadInitialIfNeeded()
        await settle()
        store.saveCurrent()
        await settle()

        store.expireUndo(assetID: "stale")
        XCTAssertEqual(store.undoAssetID, "a")

        store.expireUndo(assetID: "a")
        XCTAssertNil(store.undoAssetID)
        XCTAssertNil(store.notice)
    }

    private func card(_ id: String, isFavorited: Bool = false) -> FlowCard {
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
            author: FlowAuthor(id: "act_1", username: "Ada", avatarURL: nil)
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
