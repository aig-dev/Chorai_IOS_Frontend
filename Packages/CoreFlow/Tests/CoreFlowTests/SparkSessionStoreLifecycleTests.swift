import Combine
import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class SparkSessionStoreLifecycleTests: XCTestCase {
    func testRootTriggerPersistsCanonicalNodeAndAllBuckets() async {
        let harness = makeHarness()
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()

        harness.store.start()
        cardSubject.send(card("ast_root", content: "Root source"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root"
            )
        )
        triggerSubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.service.triggerCalls.first?.sourceAssetID, "ast_root")
        XCTAssertNil(harness.service.triggerCalls.first?.parentActivityID)
        XCTAssertEqual(harness.store.activeActivityID, "act_root")
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_root"])
        XCTAssertEqual(harness.store.results.map(\.bucket), [.angles, .keywords])
        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertEqual(harness.persistence.lastSaved?.activeActivityID, "act_root")
        XCTAssertNil(harness.persistence.lastSaved?.pendingTrigger)
    }

    func testSecondStartWhileSourceLoadsDoesNotPostOrFetchTwice() {
        let harness = makeHarness()
        _ = harness.service.enqueueCard()

        harness.store.start()
        harness.store.start()

        XCTAssertEqual(harness.service.requestedCardIDs, ["ast_root"])
        XCTAssertTrue(harness.service.triggerCalls.isEmpty)
    }

    func testRootLoadRetryFetchesSourceAgainAndTriggersOnce() async {
        let harness = makeHarness()
        let failedSource = harness.service.enqueueCard()

        harness.store.start()
        failedSource.send(completion: .failure(.timeout))
        await settle()

        let retrySource = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()
        harness.store.retryTrigger()
        retrySource.send(card("ast_root", content: "Recovered root"))
        retrySource.send(completion: .finished)
        await settle()
        triggerSubject.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root"
            )
        )
        triggerSubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(
            harness.service.requestedCardIDs,
            ["ast_root", "ast_root"]
        )
        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.store.phase, .loaded)
    }

    func testAdvanceChangesOnlyLocalIndexAndPersistsIt() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 3)
        let triggerCount = harness.service.triggerCalls.count
        _ = harness.service.enqueueMore()

        harness.store.advance()

        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.persistence.lastSaved?.nodes.first?.visibleIndex, 1)
        XCTAssertEqual(harness.service.triggerCalls.count, triggerCount)
    }

    func testSparkDeeperUsesVisibleResultAndCurrentActivityAsParent() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 2)
        let childTrigger = harness.service.enqueueTrigger()
        let expectedSource = try! XCTUnwrap(harness.store.currentResult?.card)

        harness.store.sparkCurrentDeeper()

        XCTAssertEqual(harness.service.triggerCalls.last?.sourceAssetID, expectedSource.id)
        XCTAssertEqual(harness.service.triggerCalls.last?.parentActivityID, "act_root")
        XCTAssertNotEqual(harness.service.triggerCalls.first?.requestKey, harness.service.triggerCalls.last?.requestKey)
        childTrigger.send(
            page(
                activity: "act_child",
                parent: "act_root",
                root: "act_root",
                depth: 1,
                source: expectedSource.id,
                prefix: "child"
            )
        )
        childTrigger.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.store.activeActivityID, "act_child")
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_root", "act_child"])
        XCTAssertEqual(harness.store.sourceCard?.id, expectedSource.id)
        XCTAssertEqual(harness.store.visibleIndex, 0)
        XCTAssertTrue(harness.store.didShowUpwardCue)
        XCTAssertEqual(harness.store.phase, .loaded)
    }

    func testChildWithInvalidRootRestoresParentAndIndex() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 3)
        _ = harness.service.enqueueMore()
        harness.store.advance()
        let childTrigger = harness.service.enqueueTrigger()

        harness.store.sparkCurrentDeeper()
        childTrigger.send(
            page(
                activity: "act_child",
                parent: "act_root",
                root: "act_wrong",
                depth: 1,
                source: "ast_result_2"
            )
        )
        childTrigger.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.store.activeActivityID, "act_root")
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_root"])
        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.store.phase, .failed("Couldn't continue this Spark."))
        XCTAssertNotNil(harness.persistence.lastSaved?.pendingTrigger)
    }

    func testChildFailureRestoresExactParentAndIndex() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 3)
        _ = harness.service.enqueueMore()
        harness.store.advance()
        let childTrigger = harness.service.enqueueTrigger()

        harness.store.sparkCurrentDeeper()
        childTrigger.send(completion: .failure(.retrievalUnavailable))
        await settle()

        XCTAssertEqual(harness.store.activeActivityID, "act_root")
        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.store.currentResult?.id, "ast_result_keyword")
        XCTAssertEqual(harness.store.phase, .failed("Spark is unavailable right now."))
    }

    func testRootTriggerFailureRetainsPendingIdentity() async {
        let harness = makeHarness()
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()

        harness.store.start()
        cardSubject.send(card("ast_root", content: "Root"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(completion: .failure(.retrievalUnavailable))
        await settle()

        XCTAssertNotNil(harness.persistence.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root")?.pendingTrigger)
        XCTAssertTrue(harness.persistence.removals.isEmpty)
        XCTAssertEqual(harness.store.phase, .failed("Spark is unavailable right now."))
    }

    func testSelectingAncestorReplaysExactActivityWithoutTriggering() async {
        let harness = makeHarness()
        await loadRootAndChild(harness)
        let triggerCount = harness.service.triggerCalls.count
        let replaySubject = harness.service.enqueueActivityResults()
        let sourceSubject = harness.service.enqueueCard()

        harness.store.selectNode(activityID: "act_root")
        replaySubject.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root",
                prefix: "replayed"
            )
        )
        replaySubject.send(completion: .finished)
        await settle()
        sourceSubject.send(card("ast_root", content: "Canonical root"))
        sourceSubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.requestedActivityIDs, ["act_root"])
        XCTAssertEqual(harness.service.triggerCalls.count, triggerCount)
        XCTAssertEqual(harness.store.activeActivityID, "act_root")
        XCTAssertEqual(harness.store.sourceCard?.content, "Canonical root")
        XCTAssertEqual(harness.store.currentResult?.id, "ast_replayed_angle")
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_root", "act_child"])
    }

    func testExistingSnapshotRehydratesActivityAndSourceWithoutPosting() async {
        let harness = makeHarness()
        harness.persistence.seed(
            SparkSessionSnapshot(
                actorID: "act_user",
                rootSourceAssetID: "ast_root",
                nodes: [
                    SparkChainNode(
                        sourceAssetID: "ast_child_source",
                        sourcePreview: "Saved child",
                        activityID: "act_child",
                        parentActivityID: "act_root",
                        rootActivityID: "act_root",
                        chainDepth: 1,
                        visibleIndex: 1
                    )
                ],
                activeActivityID: "act_child",
                pendingTrigger: nil,
                didShowUpwardCue: true
            )
        )
        let replaySubject = harness.service.enqueueActivityResults()
        let sourceSubject = harness.service.enqueueCard()

        harness.store.start()
        replaySubject.send(
            page(
                activity: "act_child",
                parent: "act_root",
                root: "act_root",
                depth: 1,
                source: "ast_child_source",
                prefix: "restored",
                resultCount: 3
            )
        )
        replaySubject.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.store.currentResult?.id, "ast_restored_keyword")
        XCTAssertEqual(harness.store.sourceCard?.id, "ast_child_source")
        XCTAssertEqual(harness.store.sourceCard?.content, "Saved child")

        sourceSubject.send(card("ast_child_source", content: "Restored source"))
        sourceSubject.send(completion: .finished)
        await settle()

        XCTAssertTrue(harness.service.triggerCalls.isEmpty)
        XCTAssertEqual(harness.service.requestedActivityIDs, ["act_child"])
        XCTAssertEqual(harness.service.requestedCardIDs, ["ast_child_source"])
        XCTAssertEqual(harness.store.visibleIndex, 1)
        XCTAssertEqual(harness.store.currentResult?.id, "ast_restored_keyword")
        XCTAssertEqual(harness.store.sourceCard?.content, "Restored source")
        XCTAssertEqual(harness.store.phase, .loaded)
    }

    func testMissingRestoredActivityRetainsSnapshotWithoutTriggering() async {
        let harness = makeHarness()
        harness.persistence.seed(
            SparkSessionSnapshot(
                actorID: "act_user",
                rootSourceAssetID: "ast_root",
                nodes: [
                    SparkChainNode(
                        sourceAssetID: "ast_root",
                        sourcePreview: "Root",
                        activityID: "act_missing",
                        parentActivityID: nil,
                        rootActivityID: "act_missing",
                        chainDepth: 0,
                        visibleIndex: 0
                    )
                ],
                activeActivityID: "act_missing",
                pendingTrigger: nil,
                didShowUpwardCue: false
            )
        )
        let replaySubject = harness.service.enqueueActivityResults()

        harness.store.start()
        replaySubject.send(completion: .failure(.notFound))
        await settle()

        XCTAssertTrue(harness.service.triggerCalls.isEmpty)
        XCTAssertTrue(harness.persistence.removals.isEmpty)
        XCTAssertEqual(harness.persistence.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root")?.activeActivityID, "act_missing")
        XCTAssertEqual(harness.store.phase, .failed("Couldn't restore this Spark."))
    }

    func testTransientReplayFailureRetriesExactActivity() async {
        let harness = makeHarness()
        harness.persistence.seed(
            SparkSessionSnapshot(
                actorID: "act_user",
                rootSourceAssetID: "ast_root",
                nodes: [
                    SparkChainNode(
                        sourceAssetID: "ast_root",
                        sourcePreview: "Saved root",
                        activityID: "act_root",
                        parentActivityID: nil,
                        rootActivityID: "act_root",
                        chainDepth: 0,
                        visibleIndex: 0
                    )
                ],
                activeActivityID: "act_root",
                pendingTrigger: nil,
                didShowUpwardCue: false
            )
        )
        let failedReplay = harness.service.enqueueActivityResults()

        harness.store.start()
        failedReplay.send(completion: .failure(.timeout))
        await settle()

        let retryReplay = harness.service.enqueueActivityResults()
        _ = harness.service.enqueueCard()
        harness.store.retryTrigger()
        retryReplay.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root"
            )
        )
        retryReplay.send(completion: .finished)
        await settle()

        XCTAssertEqual(
            harness.service.requestedActivityIDs,
            ["act_root", "act_root"]
        )
        XCTAssertEqual(harness.store.phase, .loaded)
    }

    func testReplaySourceRefreshFailureKeepsRestoredDeckUsable() async {
        let harness = makeHarness()
        harness.persistence.seed(
            SparkSessionSnapshot(
                actorID: "act_user",
                rootSourceAssetID: "ast_root",
                nodes: [
                    SparkChainNode(
                        sourceAssetID: "ast_root",
                        sourcePreview: "Saved root",
                        activityID: "act_root",
                        parentActivityID: nil,
                        rootActivityID: "act_root",
                        chainDepth: 0,
                        visibleIndex: 0
                    )
                ],
                activeActivityID: "act_root",
                pendingTrigger: nil,
                didShowUpwardCue: false
            )
        )
        let replaySubject = harness.service.enqueueActivityResults()
        let sourceSubject = harness.service.enqueueCard()

        harness.store.start()
        replaySubject.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root"
            )
        )
        replaySubject.send(completion: .finished)
        await settle()
        sourceSubject.send(completion: .failure(.timeout))
        await settle()

        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertEqual(harness.store.sourceCard?.content, "Saved root")
        XCTAssertNotNil(harness.store.currentResult)
    }

    func testAcknowledgedResultFailurePersistsActivityAndRetriesOnlyItsRead() async {
        let harness = makeHarness()
        let source = harness.service.enqueueCard()
        let trigger = harness.service.enqueueTrigger()
        harness.store.start()
        source.send(card("ast_root", content: "Root"))
        source.send(completion: .finished)
        await settle()
        trigger.send(completion: .failure(.resultsUnavailable(
            activityID: "act_original", rootActivityID: "act_original", chainDepth: 0
        )))
        await settle()

        XCTAssertEqual(harness.store.activeActivityID, "act_original")
        XCTAssertEqual(harness.persistence.lastSaved?.activeActivityID, "act_original")
        XCTAssertNil(harness.persistence.lastSaved?.pendingTrigger)
        XCTAssertEqual(harness.store.phase, .failed("Spark completed, but its results couldn't load."))
        let failedRead = harness.service.enqueueActivityResults()
        harness.store.retryTrigger()
        failedRead.send(completion: .failure(.retrievalUnavailable))
        await settle()
        let recoveredRead = harness.service.enqueueActivityResults()
        _ = harness.service.enqueueCard()
        harness.store.retryTrigger()
        recoveredRead.send(page(activity: "act_original", parent: nil, root: "act_original", depth: 0, source: "ast_root"))
        recoveredRead.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.triggerCalls.count, 1)
        XCTAssertEqual(harness.service.requestedActivityIDs, ["act_original", "act_original"])
        XCTAssertTrue(harness.service.historyCalls.isEmpty)
        XCTAssertEqual(harness.store.phase, .loaded)
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_original"])
    }

    func testRestartAfterAcknowledgedResultFailureReadsPersistedActivityWithoutTrigger() async {
        let harness = makeHarness()
        let source = harness.service.enqueueCard()
        let trigger = harness.service.enqueueTrigger()
        harness.store.start()
        source.send(card("ast_root", content: "Root"))
        source.send(completion: .finished)
        await settle()
        trigger.send(completion: .failure(.resultsUnavailable(
            activityID: "act_original", rootActivityID: "act_original", chainDepth: 0
        )))
        await settle()

        let service = MockCoreSparkService()
        let read = service.enqueueActivityResults()
        _ = service.enqueueCard()
        let restarted = SparkSessionStore(
            actorID: "act_user", rootSourceAssetID: "ast_root",
            service: service, persistence: harness.persistence
        )
        restarted.start()
        read.send(page(activity: "act_original", parent: nil, root: "act_original", depth: 0, source: "ast_root"))
        read.send(completion: .finished)
        await settle()

        XCTAssertEqual(service.requestedActivityIDs, ["act_original"])
        XCTAssertTrue(service.triggerCalls.isEmpty)
        XCTAssertTrue(service.historyCalls.isEmpty)
        XCTAssertEqual(restarted.phase, .loaded)
        XCTAssertEqual(restarted.activeActivityID, "act_original")
    }

    func testAcknowledgedChildRemainsInHistoryWhenRevisitingItsParent() async {
        let harness = makeHarness()
        await loadRoot(harness, resultCount: 2)
        let sourceID = harness.store.currentResult!.id
        let trigger = harness.service.enqueueTrigger()
        harness.store.sparkCurrentDeeper()
        trigger.send(completion: .failure(.resultsUnavailable(
            activityID: "act_child", rootActivityID: "act_root", chainDepth: 1
        )))
        await settle()
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_root", "act_child"])
        XCTAssertEqual(harness.store.activeActivityID, "act_child")
        XCTAssertEqual(harness.persistence.lastSaved?.nodes.last?.parentActivityID, "act_root")

        let parentRead = harness.service.enqueueActivityResults()
        _ = harness.service.enqueueCard()
        harness.store.selectNode(activityID: "act_root")
        parentRead.send(page(activity: "act_root", parent: nil, root: "act_root", depth: 0, source: "ast_root"))
        parentRead.send(completion: .finished)
        await settle()
        let childRead = harness.service.enqueueActivityResults()
        _ = harness.service.enqueueCard()
        harness.store.selectNode(activityID: "act_child")
        childRead.send(page(activity: "act_child", parent: "act_root", root: "act_root", depth: 1, source: sourceID))
        childRead.send(completion: .finished)
        await settle()

        XCTAssertEqual(harness.service.triggerCalls.count, 2)
        XCTAssertEqual(harness.service.requestedActivityIDs, ["act_root", "act_child"])
        XCTAssertEqual(harness.store.chain.map(\.activityID), ["act_root", "act_child"])
        XCTAssertEqual(harness.store.activeActivityID, "act_child")
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
        resultCount: Int
    ) async {
        let cardSubject = harness.service.enqueueCard()
        let triggerSubject = harness.service.enqueueTrigger()
        harness.store.start()
        cardSubject.send(card("ast_root", content: "Root"))
        cardSubject.send(completion: .finished)
        await settle()
        triggerSubject.send(
            page(
                activity: "act_root",
                parent: nil,
                root: "act_root",
                depth: 0,
                source: "ast_root",
                resultCount: resultCount
            )
        )
        triggerSubject.send(completion: .finished)
        await settle()
    }

    private func loadRootAndChild(_ harness: Harness) async {
        await loadRoot(harness, resultCount: 2)
        let childTrigger = harness.service.enqueueTrigger()
        let childSourceID = try! XCTUnwrap(harness.store.currentResult?.id)
        harness.store.sparkCurrentDeeper()
        childTrigger.send(
            page(
                activity: "act_child",
                parent: "act_root",
                root: "act_root",
                depth: 1,
                source: childSourceID,
                prefix: "child"
            )
        )
        childTrigger.send(completion: .finished)
        await settle()
    }

    private func page(
        activity: String,
        parent: String?,
        root: String,
        depth: Int,
        source: String,
        prefix: String = "result",
        resultCount: Int = 2
    ) -> SparkActivityPage {
        var angleResults: [SparkResult] = []
        var keywordResults: [SparkResult] = []
        if resultCount > 0 {
            angleResults.append(result("ast_\(prefix)_angle", bucket: .angles))
        }
        if resultCount > 1 {
            keywordResults.append(result("ast_\(prefix)_keyword", bucket: .keywords))
        }
        if resultCount > 2 {
            keywordResults.append(result("ast_\(prefix)_third", bucket: .keywords))
        }
        return SparkActivityPage(
            activityID: activity,
            parentActivityID: parent,
            rootActivityID: root,
            chainDepth: depth,
            sourceAssetID: source,
            groups: [
                .related: [],
                .angles: angleResults,
                .keywords: keywordResults
            ],
            createdAt: Date(timeIntervalSince1970: 1_001)
        )
    }

    private func result(
        _ id: String,
        bucket: SparkBucket
    ) -> SparkResult {
        SparkResult(
            card: card(id, content: id),
            bucket: bucket,
            score: 0.9,
            resultID: "sr_\(id)"
        )
    }

    private func card(
        _ id: String,
        content: String
    ) -> FlowCard {
        FlowCard(
            id: id,
            title: nil,
            content: content,
            contentHash: nil,
            tags: [],
            isPublic: true,
            createdAt: "",
            updatedAt: "",
            favoriteCount: 0,
            likeCount: 0,
            commentCount: 0,
            rate: 0,
            isFavorited: false,
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
}
