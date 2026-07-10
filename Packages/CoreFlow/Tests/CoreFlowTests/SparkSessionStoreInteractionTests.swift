import Combine
import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class SparkSessionStoreInteractionTests: XCTestCase {
    func testSaveCarriesActivityAdvancesOptimisticallyAndLocksDuplicates() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 4)
        let favoriteSubject = harness.service.enqueueFavorite()

        harness.store.saveCurrent()
        harness.store.saveCurrent()

        XCTAssertEqual(
            harness.service.favoriteCalls,
            [.init(assetID: "ast_result_1", sparkActivityID: "act_root")]
        )
        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertTrue(harness.store.isInteractionLocked)

        favoriteSubject.send(())
        favoriteSubject.send(completion: .finished)
        await settle()

        XCTAssertFalse(harness.store.isInteractionLocked)
        XCTAssertEqual(harness.store.notice, .saved(assetID: "ast_result_1"))
        XCTAssertTrue(harness.store.canUndoSave)
    }

    func testSaveFailureRestoresExactResultAndIndex() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 4)
        harness.store.advance()
        let favoriteSubject = harness.service.enqueueFavorite()

        harness.store.saveCurrent()
        favoriteSubject.send(completion: .failure(.server))
        await settle()

        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.store.currentResult?.id, "ast_result_2")
        XCTAssertEqual(harness.store.notice, .saveFailed)
        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertFalse(harness.store.isInteractionLocked)
    }

    func testUndoNewFavoriteUnfavoritesAndRestoresSavedResult() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 3)
        let favoriteSubject = harness.service.enqueueFavorite()
        _ = harness.service.enqueueMore()

        harness.store.saveCurrent()
        favoriteSubject.send(())
        favoriteSubject.send(completion: .finished)
        await settle()
        let unfavoriteSubject = harness.service.enqueueUnfavorite()

        harness.store.undoLastSave()

        XCTAssertEqual(harness.service.unfavoriteAssetIDs, ["ast_result_1"])
        XCTAssertEqual(harness.store.visibleIndex, 0)
        XCTAssertEqual(harness.store.currentResult?.id, "ast_result_1")
        XCTAssertTrue(harness.store.isInteractionLocked)

        unfavoriteSubject.send(())
        unfavoriteSubject.send(completion: .finished)
        await settle()

        XCTAssertFalse(harness.store.isInteractionLocked)
        XCTAssertNil(harness.store.notice)
        XCTAssertFalse(harness.store.canUndoSave)
    }

    func testAlreadyFavoritedResultAttachesContextWithoutUndoOrUnfavorite() async {
        let harness = makeHarness()
        await loadRoot(
            harness,
            resultCount: 3,
            firstResultIsFavorited: true
        )
        let favoriteSubject = harness.service.enqueueFavorite()
        _ = harness.service.enqueueMore()

        harness.store.saveCurrent()
        favoriteSubject.send(())
        favoriteSubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(
            harness.service.favoriteCalls,
            [.init(assetID: "ast_result_1", sparkActivityID: "act_root")]
        )
        XCTAssertFalse(harness.store.canUndoSave)

        harness.store.undoLastSave()

        XCTAssertTrue(harness.service.unfavoriteAssetIDs.isEmpty)
        XCTAssertEqual(harness.store.visibleIndex, 1)
    }

    func testUndoFailureReturnsToPostSaveIndexAndCanRetry() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 3)
        let favoriteSubject = harness.service.enqueueFavorite()
        _ = harness.service.enqueueMore()
        harness.store.saveCurrent()
        favoriteSubject.send(())
        favoriteSubject.send(completion: .finished)
        await settle()
        let firstUnfavorite = harness.service.enqueueUnfavorite()

        harness.store.undoLastSave()
        firstUnfavorite.send(completion: .failure(.server))
        await settle()

        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.store.notice, .undoFailed)
        XCTAssertTrue(harness.store.canUndoSave)

        let retryUnfavorite = harness.service.enqueueUnfavorite()
        harness.store.undoLastSave()
        retryUnfavorite.send(())
        retryUnfavorite.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.unfavoriteAssetIDs.count, 2)
        XCTAssertEqual(harness.store.visibleIndex, 0)
        XCTAssertNil(harness.store.notice)
    }

    func testSavedNoticeExpiresByAssetEvenWhenFavoriteAlreadyExisted() async {
        let harness = makeHarness()
        await loadRoot(
            harness,
            resultCount: 3,
            firstResultIsFavorited: true
        )
        let favoriteSubject = harness.service.enqueueFavorite()
        _ = harness.service.enqueueMore()
        harness.store.saveCurrent()
        favoriteSubject.send(())
        favoriteSubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.store.savedAssetID, "ast_result_1")
        XCTAssertNil(harness.store.undoAssetID)

        harness.store.expireUndo(assetID: "ast_other")
        XCTAssertEqual(harness.store.notice, .saved(assetID: "ast_result_1"))

        harness.store.expireUndo(assetID: "ast_result_1")
        XCTAssertNil(harness.store.notice)
        XCTAssertNil(harness.store.savedAssetID)
    }

    func testMoreDeduplicatesSourceAndStopsAfterTwoEmptyBatches() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 4)
        harness.store.advance()
        let firstMore = harness.service.enqueueMore()

        harness.store.advance()

        XCTAssertEqual(
            harness.service.moreCalls,
            [.init(sourceAssetID: "ast_root", cursor: nil, limit: 20)]
        )
        firstMore.send(
            SparkMorePage(
                results: [
                    result("ast_root"),
                    result("ast_result_2"),
                    result("ast_result_5")
                ],
                nextCursor: "cursor-1",
                round: 0,
                sourceAssetID: "ast_root"
            )
        )
        firstMore.send(completion: .finished)
        await settle()
        XCTAssertEqual(
            harness.store.results.map(\.id),
            ["ast_result_1", "ast_result_2", "ast_result_3", "ast_result_4", "ast_result_5"]
        )

        let secondMore = harness.service.enqueueMore()
        harness.store.advance()
        XCTAssertEqual(harness.service.moreCalls.last?.cursor, "cursor-1")
        secondMore.send(
            SparkMorePage(
                results: [],
                nextCursor: "cursor-2",
                round: 1,
                sourceAssetID: "ast_root"
            )
        )
        secondMore.send(completion: .finished)
        await settle()

        let thirdMore = harness.service.enqueueMore()
        harness.store.advance()
        XCTAssertEqual(harness.service.moreCalls.last?.cursor, "cursor-2")
        thirdMore.send(
            SparkMorePage(
                results: [result("ast_result_4")],
                nextCursor: "cursor-3",
                round: 2,
                sourceAssetID: "ast_root"
            )
        )
        thirdMore.send(completion: .finished)
        await settle()

        XCTAssertTrue(harness.store.isMoreExhausted)
        let requestCount = harness.service.moreCalls.count
        harness.store.advance()
        XCTAssertEqual(harness.service.moreCalls.count, requestCount)
    }

    func testMoreFailureKeepsDeckUsable() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 3)
        let moreSubject = harness.service.enqueueMore()

        harness.store.advance()
        moreSubject.send(completion: .failure(.retrievalUnavailable))
        await settle()

        XCTAssertEqual(harness.store.currentResult?.id, "ast_result_2")
        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertEqual(harness.store.notice, .moreFailed)
    }

    func testEmptyDeckAutomaticallyChecksSecondEmptyPageThenStops() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 1)
        let firstMore = harness.service.enqueueMore()
        let secondMore = harness.service.enqueueMore()

        harness.store.advance()
        firstMore.send(
            SparkMorePage(
                results: [result("ast_result_1")],
                nextCursor: "cursor-1",
                round: 0,
                sourceAssetID: "ast_root"
            )
        )
        firstMore.send(completion: .finished)
        await waitUntil { harness.service.moreCalls.count == 2 }

        XCTAssertEqual(harness.service.moreCalls.count, 2)
        secondMore.send(
            SparkMorePage(
                results: [],
                nextCursor: "cursor-2",
                round: 1,
                sourceAssetID: "ast_root"
            )
        )
        secondMore.send(completion: .finished)
        await waitUntil { harness.store.isMoreExhausted }

        XCTAssertTrue(harness.store.isMoreExhausted)
        XCTAssertEqual(harness.store.phase, .empty)
        XCTAssertEqual(harness.service.moreCalls.count, 2)
    }

    func testAmbiguousTriggerReconcilesHistoryWithoutSecondPost() async {
        let harness = makeHarness()
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()
        let historySubject = harness.service.enqueueHistory()
        let replaySubject = harness.service.enqueueActivityResults()
        let replayCardSubject = harness.service.enqueueCard()

        harness.store.start()
        cardSubject.send(card("ast_root"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(completion: .failure(.timeout))
        await settle()

        XCTAssertEqual(harness.store.phase, .reconciling)
        XCTAssertEqual(harness.service.historyCalls.count, 1)
        historySubject.send([
            SparkHistoryEntry(
                activityID: "act_recovered",
                parentActivityID: nil,
                sourceAssetID: "ast_root",
                rootActivityID: "act_recovered",
                chainDepth: 0,
                createdAt: Date(timeIntervalSince1970: 1_001)
            )
        ])
        historySubject.send(completion: .finished)
        await settle()
        replaySubject.send(
            page(
                activity: "act_recovered",
                parent: nil,
                root: "act_recovered",
                depth: 0,
                source: "ast_root",
                resultCount: 2
            )
        )
        replaySubject.send(completion: .finished)
        await settle()
        replayCardSubject.send(card("ast_root"))
        replayCardSubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.store.activeActivityID, "act_recovered")
        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertNil(harness.persistence.lastSaved?.pendingTrigger)
    }

    func testNoHistoryMatchRequiresExplicitRetryBeforeSecondPost() async {
        let harness = makeHarness()
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()
        let historySubject = harness.service.enqueueHistory()

        harness.store.start()
        cardSubject.send(card("ast_root"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(completion: .failure(.offline))
        await settle()
        historySubject.send([])
        historySubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.store.phase, .failed("Couldn't confirm this Spark."))
        XCTAssertFalse(harness.store.isInteractionLocked)

        _ = harness.service.enqueueTrigger()
        harness.store.retryTrigger()

        XCTAssertEqual(harness.service.triggerCalls.count, 2)
    }

    func testHistoryCheckFailureRetriesHistoryInsteadOfPostingAgain() async {
        let harness = makeHarness()
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()
        let firstHistory = harness.service.enqueueHistory()

        harness.store.start()
        cardSubject.send(card("ast_root"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(completion: .failure(.timeout))
        await settle()
        firstHistory.send(completion: .failure(.offline))
        await settle()

        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.service.historyCalls.count, 1)
        XCTAssertNotNil(harness.persistence.lastSaved?.pendingTrigger)
        XCTAssertEqual(harness.store.phase, .failed("Couldn't check this Spark."))

        _ = harness.service.enqueueHistory()
        harness.store.retryTrigger()

        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.service.historyCalls.count, 2)
        XCTAssertEqual(harness.store.phase, .reconciling)
    }

    func testPersistedPendingTriggerReconcilesOnStartWithoutPosting() async {
        let harness = makeHarness()
        harness.persistence.seed(
            SparkSessionSnapshot(
                actorID: "act_user",
                rootSourceAssetID: "ast_root",
                nodes: [],
                activeActivityID: nil,
                pendingTrigger: PendingSparkTrigger(
                    sourceAssetID: "ast_root",
                    sourcePreview: "Root",
                    parentActivityID: nil,
                    startedAt: Date(timeIntervalSince1970: 1_000),
                    priorActivityID: nil,
                    priorVisibleIndex: 0
                ),
                didShowUpwardCue: false
            )
        )
        let historySubject = harness.service.enqueueHistory()
        let replaySubject = harness.service.enqueueActivityResults()
        let sourceSubject = harness.service.enqueueCard()

        harness.store.start()

        XCTAssertTrue(harness.service.triggerCalls.isEmpty)
        XCTAssertEqual(harness.service.historyCalls.count, 1)
        historySubject.send([
            SparkHistoryEntry(
                activityID: "act_recovered",
                parentActivityID: nil,
                sourceAssetID: "ast_root",
                rootActivityID: "act_recovered",
                chainDepth: 0,
                createdAt: Date(timeIntervalSince1970: 1_001)
            )
        ])
        historySubject.send(completion: .finished)
        await settle()
        replaySubject.send(
            page(
                activity: "act_recovered",
                parent: nil,
                root: "act_recovered",
                depth: 0,
                source: "ast_root",
                resultCount: 2
            )
        )
        replaySubject.send(completion: .finished)
        await settle()
        sourceSubject.send(card("ast_root"))
        sourceSubject.send(completion: .finished)
        await settle()

        XCTAssertTrue(harness.service.triggerCalls.isEmpty)
        XCTAssertEqual(harness.store.activeActivityID, "act_recovered")
        XCTAssertEqual(harness.store.phase, .loaded)
    }

    private typealias Harness = (
        store: SparkSessionStore,
        service: MockCoreSparkService,
        persistence: InMemorySparkSessionPersistence
    )

    private func makeHarness() -> Harness {
        let service = MockCoreSparkService()
        let persistence = InMemorySparkSessionPersistence()
        let store = SparkSessionStore(
            actorID: "act_user",
            rootSourceAssetID: "ast_root",
            service: service,
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        return (store, service, persistence)
    }

    private func loadRoot(
        _ harness: Harness,
        resultCount: Int,
        firstResultIsFavorited: Bool = false
    ) async {
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()
        harness.store.start()
        cardSubject.send(card("ast_root"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root",
                resultCount: resultCount,
                firstResultIsFavorited: firstResultIsFavorited
            )
        )
        triggerSubject.send(completion: .finished)
        await settle()
    }

    private func page(
        activity: String,
        parent: String?,
        root: String,
        depth: Int,
        source: String,
        resultCount: Int,
        firstResultIsFavorited: Bool = false
    ) -> SparkActivityPage {
        let pageResults = (resultCount > 0 ? Array(1...resultCount) : []).map { index in
            result(
                "ast_result_\(index)",
                isFavorited: index == 1 && firstResultIsFavorited
            )
        }
        return SparkActivityPage(
            activityID: activity,
            parentActivityID: parent,
            rootActivityID: root,
            chainDepth: depth,
            sourceAssetID: source,
            groups: [.related: pageResults, .angles: [], .keywords: []],
            createdAt: Date(timeIntervalSince1970: 1_001)
        )
    }

    private func result(
        _ id: String,
        isFavorited: Bool = false
    ) -> SparkResult {
        SparkResult(
            card: card(id, isFavorited: isFavorited),
            bucket: .related,
            score: 0.9,
            resultID: "sr_\(id)"
        )
    }

    private func card(
        _ id: String,
        isFavorited: Bool = false
    ) -> FlowCard {
        FlowCard(
            id: id,
            title: nil,
            content: id,
            contentHash: nil,
            tags: [],
            isPublic: true,
            createdAt: "",
            updatedAt: "",
            favoriteCount: isFavorited ? 1 : 0,
            likeCount: 0,
            commentCount: 0,
            rate: 0,
            isFavorited: isFavorited,
            isLiked: false,
            isPinned: false,
            pinnedAt: nil,
            author: nil
        )
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail(
            "Timed out waiting for asynchronous Spark state",
            file: file,
            line: line
        )
    }
}
