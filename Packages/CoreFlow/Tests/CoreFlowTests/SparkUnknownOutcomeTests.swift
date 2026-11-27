import Combine
import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class SparkUnknownOutcomeTests: XCTestCase {
    func testEmptyHistoryKeepsOriginalRequestIdentityForExplicitRetry() async {
        let (store, service, persistence) = harness()
        let source = service.enqueueCard()
        let trigger = service.enqueueTrigger()
        let history = service.enqueueHistory()
        store.start()
        source.send(card()); source.send(completion: .finished)
        await settle()
        trigger.send(completion: .failure(.timeout))
        await settle()
        history.send([]); history.send(completion: .finished)
        await settle()
        XCTAssertNotNil(persistence.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root")?.pendingTrigger)
        _ = service.enqueueTrigger()
        _ = service.enqueueHistory()
        store.retryTrigger()
        await settle()
        XCTAssertEqual(service.triggerCalls.count, 2)
        XCTAssertEqual(service.triggerCalls.first, service.triggerCalls.last)
        XCTAssertEqual(service.triggerCalls.first?.requestKey, persistence.lastSaved?.pendingTrigger?.requestKey)
        XCTAssertTrue(service.historyCalls.isEmpty)
    }

    func testRecentHistoryFromAnotherWindowCannotIdentifyTheLostExecution() async {
        let (store, service, persistence) = harness()
        let source = service.enqueueCard()
        let trigger = service.enqueueTrigger()
        let history = service.enqueueHistory()
        _ = service.enqueueActivityResults()
        _ = service.enqueueCard()
        store.start()
        source.send(card()); source.send(completion: .finished)
        await settle()
        trigger.send(completion: .failure(.timeout))
        await settle()
        history.send([SparkHistoryEntry(
            activityID: "act_other_window", parentActivityID: nil, sourceAssetID: "ast_root",
            rootActivityID: "act_other_window", chainDepth: 0, createdAt: Date(timeIntervalSince1970: 1_001)
        )])
        history.send(completion: .finished)
        await settle()
        XCTAssertNil(store.activeActivityID, "Source, parent and time do not uniquely identify a paid request")
        XCTAssertTrue(service.requestedActivityIDs.isEmpty)
        XCTAssertNotNil(persistence.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root")?.pendingTrigger)
    }

    func testMalformedResponseKeepsOriginalRequestIdentityForExplicitRetry() async {
        let (store, service, persistence) = harness()
        let source = service.enqueueCard()
        let trigger = service.enqueueTrigger()
        _ = service.enqueueHistory()
        store.start()
        source.send(card()); source.send(completion: .finished)
        await settle()
        trigger.send(completion: .failure(.decoding))
        await settle()
        XCTAssertNotNil(persistence.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root")?.pendingTrigger)
        _ = service.enqueueTrigger()
        _ = service.enqueueHistory()
        store.retryTrigger()
        await settle()
        XCTAssertEqual(service.triggerCalls.count, 2)
        XCTAssertEqual(service.triggerCalls.first, service.triggerCalls.last)
        XCTAssertTrue(service.historyCalls.isEmpty)
    }

    func testRestartAfterUnknownOutcomeUsesFrozenRequestWithoutHistory() async {
        let (first, service, persistence) = harness()
        let source = service.enqueueCard(), trigger = service.enqueueTrigger()
        first.start(); source.send(card()); source.send(completion: .finished)
        await settle(); trigger.send(completion: .failure(.timeout)); await settle()
        let key = persistence.lastSaved?.pendingTrigger?.requestKey
        let restartedService = MockCoreSparkService()
        _ = restartedService.enqueueTrigger()
        let restarted = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: restartedService, persistence: persistence)
        restarted.start()
        XCTAssertEqual(restartedService.triggerCalls.first?.requestKey, key)
        XCTAssertEqual(restartedService.triggerCalls.first, service.triggerCalls.first)
        XCTAssertTrue(restartedService.requestedCardIDs.isEmpty)
        XCTAssertTrue(restartedService.historyCalls.isEmpty)
    }

    func testEveryOutcomeContextRetainsExactAttemptAndCorrectRecoveryMethod() async {
        for reason in SparkExecutionOutcome.Reason.allCases {
            let (store, service, persistence) = harness()
            let source = service.enqueueCard(), trigger = service.enqueueTrigger()
            store.start(); source.send(card()); source.send(completion: .finished)
            await settle()
            let outcome = SparkExecutionOutcome(reason: reason, activityID: "act_original")
            trigger.send(completion: .failure(.executionOutcome(outcome))); await settle()
            let pending = persistence.lastSaved?.pendingTrigger
            XCTAssertEqual(pending?.attemptActivityID, "act_original", reason.rawValue)
            XCTAssertEqual(pending?.committedActivityID, outcome.isCommitted ? "act_original" : nil)
            if outcome.isCommitted { _ = service.enqueueActivityResults() } else { _ = service.enqueueTrigger() }
            store.retryTrigger()
            XCTAssertEqual(service.triggerCalls.count, outcome.isCommitted ? 1 : 2, reason.rawValue)
            XCTAssertEqual(service.requestedActivityIDs, outcome.isCommitted ? ["act_original"] : [])
            XCTAssertEqual(service.triggerCalls.first?.requestKey, service.triggerCalls.last?.requestKey)
            XCTAssertTrue(service.historyCalls.isEmpty)
        }
    }

    func testKnownOutcomeSurvivesReadDenialAndRestartWithoutPosting() async {
        for error in [CoreSparkError.forbidden, .notFound, .decoding] {
            let (store, service, persistence) = harness()
            let source = service.enqueueCard(), trigger = service.enqueueTrigger()
            store.start(); source.send(card()); source.send(completion: .finished)
            await settle()
            trigger.send(completion: .failure(.executionOutcome(.init(reason: .committedReplyUnavailable, activityID: "act_original"))))
            await settle()
            let read = service.enqueueActivityResults(); store.retryTrigger()
            read.send(completion: .failure(error)); await settle()
            XCTAssertEqual(persistence.lastSaved?.pendingTrigger?.committedActivityID, "act_original")
            let restartedService = MockCoreSparkService()
            _ = restartedService.enqueueActivityResults()
            let restarted = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: restartedService, persistence: persistence)
            restarted.start()
            XCTAssertTrue(restartedService.triggerCalls.isEmpty)
            XCTAssertEqual(restartedService.requestedActivityIDs, ["act_original"])
        }
    }

    func testContradictoryAttemptIdentityIsNotAdopted() async {
        let (store, service, persistence) = harness()
        let source = service.enqueueCard(), trigger = service.enqueueTrigger()
        store.start(); source.send(card()); source.send(completion: .finished); await settle()
        trigger.send(completion: .failure(.executionOutcome(.init(reason: .commitUnknown, activityID: "act_original"))))
        await settle()
        let retry = service.enqueueTrigger(); store.retryTrigger()
        retry.send(page(activity: "act_other")); retry.send(completion: .finished); await settle()
        XCTAssertNil(store.activeActivityID)
        XCTAssertEqual(persistence.lastSaved?.pendingTrigger?.attemptActivityID, "act_original")
        XCTAssertEqual(service.triggerCalls.first, service.triggerCalls.last)
    }

    func testCommittedReplayRejectsEveryChangedChainCoordinate() async {
        for page in [page(source: "ast_other"), page(parent: "act_other"), page(root: "act_other"), page(depth: 1)] {
            let service = MockCoreSparkService(), persistence = InMemorySparkSessionPersistence()
            persistence.seed(.init(actorID: "act_user", rootSourceAssetID: "ast_root",
                nodes: [.init(sourceAssetID: "ast_root", sourcePreview: "Root", activityID: "act_original", parentActivityID: nil,
                    rootActivityID: "act_original", chainDepth: 0, visibleIndex: 0)],
                activeActivityID: "act_original", pendingTrigger: nil, didShowUpwardCue: false))
            let read = service.enqueueActivityResults()
            let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service, persistence: persistence)
            store.start(); read.send(page); read.send(completion: .finished); await settle()
            XCTAssertEqual(store.phase, .failed("Couldn't restore this Spark."))
            XCTAssertTrue(service.requestedCardIDs.isEmpty)
            XCTAssertTrue(service.triggerCalls.isEmpty)
            XCTAssertEqual(persistence.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root")?.activeActivityID, "act_original")
        }
    }

    func testFailedInitialPersistenceBlocksDispatchAndKeepsKeyForRetry() async {
        let persistence = FailingSparkPersistence(), service = MockCoreSparkService()
        persistence.rejectSave = true
        let source = service.enqueueCard()
        let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service, persistence: persistence)
        store.start(); source.send(card()); source.send(completion: .finished); await settle()
        XCTAssertTrue(service.triggerCalls.isEmpty)
        let attemptedKey = persistence.attempted?.pendingTrigger?.requestKey
        persistence.rejectSave = false
        _ = service.enqueueTrigger(); store.retryTrigger()
        XCTAssertEqual(service.triggerCalls.first?.requestKey, attemptedKey)
        XCTAssertEqual(persistence.saved?.pendingTrigger?.requestKey, attemptedKey)
    }

    func testReceiptPersistenceFailureCanRetryOriginalActivityInMemory() async {
        let persistence = FailingSparkPersistence(), service = MockCoreSparkService()
        let source = service.enqueueCard(), trigger = service.enqueueTrigger()
        let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service, persistence: persistence)
        store.start(); source.send(card()); source.send(completion: .finished); await settle()
        let key = persistence.saved?.pendingTrigger?.requestKey
        persistence.rejectSave = true
        trigger.send(page()); trigger.send(completion: .finished); await settle()
        XCTAssertEqual(persistence.saved?.pendingTrigger?.requestKey, key)
        _ = service.enqueueActivityResults(); store.retryTrigger()
        XCTAssertEqual(service.requestedActivityIDs, ["act_original"])
        XCTAssertEqual(service.triggerCalls.count, 1)
    }

    func testCorruptPersistentSlotBlocksStartAndRetryWithoutDeletingBytes() async throws {
        let suite = "SparkUnknownOutcomeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "corrupt.act_user.ast_root"
        defaults.set("unreadable recovery record", forKey: key)
        let service = MockCoreSparkService()
        let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service,
            persistence: UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "corrupt"))
        store.start()
        store.applyFavoriteState(CardFavoriteState(cardID: "unrelated", isFavorited: true, favoriteCount: 1))
        XCTAssertEqual(defaults.string(forKey: key), "unreadable recovery record")
        _ = service.enqueueCard()
        store.retryTrigger()
        XCTAssertTrue(service.triggerCalls.isEmpty)
        XCTAssertTrue(service.requestedCardIDs.isEmpty)
        XCTAssertEqual(defaults.string(forKey: key), "unreadable recovery record")
    }

    func testWrongSourceReadCannotTriggerDifferentAsset() async {
        let (store, service, _) = harness()
        let source = service.enqueueCard()
        _ = service.enqueueTrigger()
        store.start(); source.send(FlowCard(id: "ast_other", title: nil, content: "Other", contentHash: nil, tags: [],
            isPublic: true, createdAt: "", updatedAt: "", favoriteCount: 0, likeCount: 0, commentCount: 0,
            rate: 0, isFavorited: false, isLiked: false, isPinned: false, pinnedAt: nil, author: nil))
        source.send(completion: .finished); await settle()
        XCTAssertTrue(service.triggerCalls.isEmpty)
    }

    func testRetryAfterSessionConflictReloadsTheSavedPendingOperation() async throws {
        try await assertSessionConflictRecovery(committed: false)
    }

    func testRetryAfterSessionConflictReadsTheSavedCommittedOperation() async throws {
        try await assertSessionConflictRecovery(committed: true)
    }

    private func assertSessionConflictRecovery(committed: Bool) async throws {
        let suite = "SparkCASRetry." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "retry")
        let service = MockCoreSparkService()
        let source = service.enqueueCard(), trigger = service.enqueueTrigger()
        let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service, persistence: persistence)
        store.start(); source.send(card()); source.send(completion: .finished); await settle()
        trigger.send(page()); trigger.send(completion: .finished); await settle()
        XCTAssertEqual(store.activeActivityID, "act_original")
        let other = UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "retry")
        var saved = try XCTUnwrap(other.snapshot(actorID: "act_user", rootSourceAssetID: "ast_root"))
        let originalKey = UUID()
        saved.pendingTrigger = PendingSparkTrigger(requestKey: originalKey,
            attemptActivityID: committed ? "act_child" : nil, committedActivityID: committed ? "act_child" : nil,
            sourceAssetID: "ast_child", sourcePreview: "Child",
            parentActivityID: "act_original", startedAt: Date(), priorActivityID: "act_original", priorVisibleIndex: 0)
        try other.save(saved)
        let bytes = defaults.data(forKey: "retry.act_user.ast_root")
        store.applyFavoriteState(.init(cardID: "unrelated", isFavorited: true, favoriteCount: 1))
        XCTAssertEqual(defaults.data(forKey: "retry.act_user.ast_root"), bytes)
        let recovery = committed ? service.enqueueActivityResults() : service.enqueueTrigger()
        store.retryTrigger(); await settle()
        XCTAssertEqual(service.triggerCalls.count, committed ? 1 : 2)
        if committed {
            XCTAssertEqual(service.requestedActivityIDs, ["act_child"])
        } else {
            XCTAssertEqual(service.triggerCalls.last?.requestKey, originalKey)
            XCTAssertEqual(service.triggerCalls.last?.sourceAssetID, "ast_child")
            XCTAssertEqual(service.triggerCalls.last?.parentActivityID, "act_original")
        }
        recovery.send(page(activity: "act_child", source: "ast_child", parent: "act_original", depth: 1))
        recovery.send(completion: .finished); await settle()
        XCTAssertEqual(store.activeActivityID, "act_child")
        XCTAssertEqual(store.sourceCard?.id, "ast_child", "A stale source card cannot label the adopted operation")
    }

    func testRetryAfterInitialSessionConflictUsesSavedKeyInsteadOfUnsentKey() async throws {
        let suite = "SparkCASInitialRetry." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = MockCoreSparkService()
        let source = service.enqueueCard()
        let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service,
            persistence: UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "initial"))
        store.start()
        let originalKey = UUID()
        let other = UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "initial")
        try other.save(.init(actorID: "act_user", rootSourceAssetID: "ast_root", nodes: [], activeActivityID: nil,
            pendingTrigger: .init(requestKey: originalKey, sourceAssetID: "ast_root", sourcePreview: "Saved root", parentActivityID: nil,
                startedAt: Date(), priorActivityID: nil, priorVisibleIndex: 0), didShowUpwardCue: false))
        source.send(card()); source.send(completion: .finished); await settle()
        XCTAssertTrue(service.triggerCalls.isEmpty)
        _ = service.enqueueTrigger(); store.retryTrigger(); await settle()
        XCTAssertEqual(service.triggerCalls.count, 1)
        XCTAssertEqual(service.triggerCalls.first?.requestKey, originalKey)
    }

    func testMissingCompetingRecordDoesNotAuthorizeNewExecutionOnRetry() async throws {
        let suite = "SparkCASMissingRetry." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = MockCoreSparkService()
        let source = service.enqueueCard(), trigger = service.enqueueTrigger()
        let store = SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service,
            persistence: UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "missing"))
        store.start(); source.send(card()); source.send(completion: .finished); await settle()
        trigger.send(page()); trigger.send(completion: .finished); await settle()
        defaults.removeObject(forKey: "missing.act_user.ast_root")
        store.applyFavoriteState(.init(cardID: "unrelated", isFavorited: true, favoriteCount: 1))
        store.retryTrigger(); store.retryTrigger(); await settle()
        XCTAssertEqual(service.triggerCalls.count, 1)
        XCTAssertEqual(service.requestedCardIDs, ["ast_root"])
        XCTAssertNil(defaults.object(forKey: "missing.act_user.ast_root"))
        guard case .failed = store.phase else { return XCTFail("A missing original record must remain recoverable, not start anew") }
    }

    private func page(activity: String = "act_original", source: String = "ast_root", parent: String? = nil,
                      root: String = "act_original", depth: Int = 0) -> SparkActivityPage {
        SparkActivityPage(activityID: activity, parentActivityID: parent, rootActivityID: root, chainDepth: depth,
            sourceAssetID: source, groups: [:], createdAt: nil)
    }

    private func harness() -> (SparkSessionStore, MockCoreSparkService, InMemorySparkSessionPersistence) {
        let service = MockCoreSparkService()
        let persistence = InMemorySparkSessionPersistence()
        return (SparkSessionStore(actorID: "act_user", rootSourceAssetID: "ast_root", service: service,
            persistence: persistence, now: { Date(timeIntervalSince1970: 1_000) }), service, persistence)
    }

    private func card() -> FlowCard {
        FlowCard(id: "ast_root", title: nil, content: "Source", contentHash: nil, tags: [],
            isPublic: true, createdAt: "", updatedAt: "", favoriteCount: 0, likeCount: 0,
            commentCount: 0, rate: 0, isFavorited: false, isLiked: false, isPinned: false,
            pinnedAt: nil, author: nil)
    }

    private func settle() async {
        await Task.yield(); await Task.yield()
    }
}

private final class FailingSparkPersistence: SparkSessionPersisting {
    var rejectSave = false
    var attempted: SparkSessionSnapshot?
    var saved: SparkSessionSnapshot?
    func snapshot(actorID: String, rootSourceAssetID: String) -> SparkSessionSnapshot? { saved }
    func save(_ snapshot: SparkSessionSnapshot) throws {
        attempted = snapshot
        if rejectSave { throw SparkSessionPersistenceError.writeFailed }
        saved = snapshot
    }
    func remove(actorID: String, rootSourceAssetID: String) { saved = nil }
}
