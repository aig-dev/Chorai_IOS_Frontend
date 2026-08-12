import Foundation
import XCTest
@testable import CoreFlow

final class OnboardingGuideStoreTests: XCTestCase {
    @MainActor
    func testNoActiveSessionStartsCanonicalV1WithoutRestart() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [.success(status(needs: true))]
        service.startResults = [.success(session(state: "elicit_signal"))]
        let store = makeStore(service: service)

        store.load(actorID: "act_1")
        await settle(3)

        XCTAssertEqual(service.startFlowVersions, [1])
        XCTAssertEqual(store.phase, .active)
        XCTAssertEqual(store.session?.state, "elicit_signal")
        XCTAssertTrue(store.shouldGuideLibraryCreation)
        XCTAssertNotNil(store.guideScene)
        XCTAssertEqual(store.contextualTipState, "elicit_signal")
    }

    @MainActor
    func testActiveV1SessionResumesCanonicalCurrentState() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "deepen_signal"))
        ]
        let store = makeStore(service: service)

        store.load(actorID: "act_1")
        await settle(3)

        XCTAssertEqual(service.currentRequestCount, 1)
        XCTAssertTrue(service.startFlowVersions.isEmpty)
        XCTAssertEqual(store.session?.state, "deepen_signal")
        XCTAssertEqual(store.guideScene?.choices.map(\.id), ["accurate"])
    }

    @MainActor
    func testActiveV2SessionIsDeferredWithoutMutation() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_web"))
        ]
        service.currentResults = [
            .success(
                session(
                    id: "onb_web",
                    version: 2,
                    state: "product_spark_intro"
                )
            )
        ]
        let store = makeStore(service: service)

        store.load(actorID: "act_1")
        await settle(3)

        XCTAssertEqual(store.phase, .deferred(flowVersion: 2))
        XCTAssertNil(store.guideScene)
        XCTAssertNil(store.contextualTipState)
        XCTAssertTrue(service.startFlowVersions.isEmpty)
        XCTAssertTrue(service.responses.isEmpty)
        XCTAssertTrue(service.skippedSessionIDs.isEmpty)
    }

    @MainActor
    func testLibraryNoteSuccessAdvancesElicitWithExactCreatedContent() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [.success(status(needs: true))]
        service.startResults = [.success(session(state: "elicit_signal"))]
        service.respondResults = [
            .success(session(state: "product_curator_intro"))
        ]
        let persistence = InMemoryOnboardingGuidePersistence()
        let store = makeStore(service: service, persistence: persistence)
        store.load(actorID: "act_1")
        await settle(3)

        let evidence = OnboardingGuideEvidence.noteCreated(
            cardID: "ast_note",
            content: "Keep this Library note"
        )
        store.receive(evidence)
        await settle(3)

        XCTAssertEqual(service.responses.count, 1)
        XCTAssertEqual(service.responses.first?.sessionID, "onb_1")
        XCTAssertEqual(
            service.responses.first?.input,
            .text("Keep this Library note")
        )
        XCTAssertEqual(store.session?.state, "product_curator_intro")
        XCTAssertTrue(
            persistence.pendingEvidence(actorID: "act_1", sessionID: "onb_1").isEmpty
        )
    }

    @MainActor
    func testDeepenUsesExactServerChoice() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [.success(session(state: "deepen_signal"))]
        service.respondResults = [
            .success(session(state: "product_curator_intro"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.deepenChoice(id: "accurate"))
        await settle(3)

        XCTAssertEqual(service.responses.map(\.input), [.choice("accurate")])
        XCTAssertEqual(store.session?.state, "product_curator_intro")
    }

    @MainActor
    func testFlowEvidenceQueuesAndAdvancesInCanonicalOrder() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_curator_intro"))
        ]
        service.respondResults = [
            .success(session(state: "product_explore_card")),
            .success(session(state: "product_spark_intro"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.flowViewed)
        store.receive(.flowCardSaved(assetID: "ast_flow"))
        await settle(6)

        XCTAssertEqual(
            service.responses.map(\.input),
            [
                .choice("activation:flow.viewed"),
                .choice("activation:explore.card_saved")
            ]
        )
        XCTAssertEqual(store.session?.state, "product_spark_intro")
    }

    @MainActor
    func testDuplicateEvidenceSendsOneCanonicalResponse() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_explore_card"))
        ]
        service.respondResults = [
            .success(session(state: "product_spark_intro"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        let evidence = OnboardingGuideEvidence.flowCardDismissed(assetID: "ast_flow")
        store.receive(evidence)
        store.receive(evidence)
        await settle(4)

        XCTAssertEqual(
            service.responses.map(\.input),
            [.choice("activation:explore.card_dismissed")]
        )
    }

    @MainActor
    func testFailedResponseKeepsEvidenceForExplicitRetry() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_explore_card"))
        ]
        service.respondResults = [
            .failure(.offline),
            .success(session(state: "product_spark_intro"))
        ]
        let persistence = InMemoryOnboardingGuidePersistence()
        let store = makeStore(service: service, persistence: persistence)
        store.load(actorID: "act_1")
        await settle(3)

        let evidence = OnboardingGuideEvidence.flowCardSaved(assetID: "ast_flow")
        store.receive(evidence)
        await settle(3)

        XCTAssertEqual(store.lastError, .offline)
        XCTAssertEqual(
            persistence.pendingEvidence(actorID: "act_1", sessionID: "onb_1"),
            [evidence]
        )

        store.retryPendingEvidence()
        await settle(3)

        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.session?.state, "product_spark_intro")
        XCTAssertEqual(service.responses.count, 2)
        XCTAssertTrue(
            persistence.pendingEvidence(actorID: "act_1", sessionID: "onb_1").isEmpty
        )
    }

    @MainActor
    func testFailedInitialNoteResponseExposesRetryableGuide() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [.success(status(needs: true))]
        service.startResults = [.success(session(state: "elicit_signal"))]
        service.respondResults = [.failure(.offline)]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.noteCreated(cardID: "ast_note", content: "Keep me"))
        await settle(3)

        XCTAssertEqual(store.lastError, .offline)
        XCTAssertNotNil(
            store.guideScene,
            "A failed note response must leave a visible retry path"
        )
    }

    @MainActor
    func testRelaunchReplaysActorSessionScopedPendingEvidence() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_explore_card"))
        ]
        service.respondResults = [
            .success(session(state: "product_spark_intro"))
        ]
        let persistence = InMemoryOnboardingGuidePersistence()
        persistence.savePendingEvidence(
            [.flowCardSaved(assetID: "ast_flow")],
            actorID: "act_1",
            sessionID: "onb_1"
        )
        let store = makeStore(service: service, persistence: persistence)

        store.load(actorID: "act_1")
        await settle(6)

        XCTAssertEqual(
            service.responses.map(\.input),
            [.choice("activation:explore.card_saved")]
        )
        XCTAssertEqual(store.session?.state, "product_spark_intro")
    }

    @MainActor
    func testSkipChangesStateOnlyAfterCanonicalSuccess() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_curator_intro"))
        ]
        service.skipResults = [
            .failure(.offline),
            .success(session(status: "skipped", state: "skipped"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        store.skip()
        await settle(3)
        XCTAssertEqual(store.phase, .active)
        XCTAssertEqual(store.lastError, .offline)

        store.skip()
        await settle(3)
        XCTAssertEqual(store.phase, .skipped)
        XCTAssertEqual(service.skippedSessionIDs, ["onb_1", "onb_1"])
    }

    @MainActor
    func testPreviousCompletionCannotUnlockNextQueuedResponse() async {
        let current = session(state: "product_curator_intro")
        let service = DeferredOnboardingGuideService(
            status: status(needs: true, activeSessionID: current.sessionID),
            current: current,
            responseCount: 2
        )
        let store = OnboardingGuideStore(
            service: service,
            persistence: InMemoryOnboardingGuidePersistence()
        )
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.flowViewed)
        store.receive(.flowCardSaved(assetID: "ast_flow"))
        XCTAssertEqual(service.responses.count, 1)
        XCTAssertTrue(store.isSending)

        service.responseSubjects[0].send(
            session(state: "product_explore_card")
        )
        await settle(2)
        XCTAssertEqual(service.responses.count, 2)
        XCTAssertTrue(store.isSending)

        service.responseSubjects[0].send(completion: .finished)
        await settle(2)
        XCTAssertTrue(
            store.isSending,
            "Finishing the previous response must not unlock the next request"
        )

        service.responseSubjects[1].send(
            session(state: "product_spark_intro")
        )
        service.responseSubjects[1].send(completion: .finished)
        await settle(2)
        XCTAssertFalse(store.isSending)
        XCTAssertEqual(store.session?.state, "product_spark_intro")
    }

    @MainActor
    func testSparkMergeAndLibraryCompleteCanonicalV1WithoutRecordReplay() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_spark_intro"))
        ]
        service.respondResults = [
            .success(session(state: "product_spark_results")),
            .success(session(state: "product_save_material")),
            .success(session(state: "product_merge_intro")),
            .success(session(state: "product_merge_preview")),
            .success(session(state: "product_library_intro")),
            .success(session(state: "build_ignite"))
        ]
        service.completeResults = [
            .success(session(status: "completed", state: "completed"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.sparkStarted(assetID: "ast_flow"))
        store.receive(.sparkResultsViewed(activityID: "act_spark"))
        store.receive(.sparkResultSaved(assetID: "ast_result"))
        store.receive(.mergeStarted(jobID: "mjob_1"))
        store.receive(.mergeCommitted(assetID: "ast_merged"))
        await settle(12)

        XCTAssertEqual(store.session?.state, "product_library_intro")
        XCTAssertEqual(service.completedSessionIDs, [])

        store.receive(.libraryViewed)
        await settle(12)

        XCTAssertEqual(
            service.responses.map(\.input),
            [
                .choice("activation:spark.started"),
                .choice("activation:spark.results_viewed"),
                .choice("activation:spark.result_saved"),
                .choice("activation:merge.started"),
                .choice("activation:merge.committed"),
                .choice("activation:library.viewed")
            ]
        )
        XCTAssertEqual(service.completedSessionIDs, ["onb_1"])
        XCTAssertEqual(store.phase, .completed)
        XCTAssertEqual(store.session?.state, "completed")
    }

    @MainActor
    func testLibraryViewedBeforePostCommitSceneIsNotQueued() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_merge_intro"))
        ]
        let persistence = InMemoryOnboardingGuidePersistence()
        let store = makeStore(service: service, persistence: persistence)
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.libraryViewed)

        XCTAssertTrue(service.responses.isEmpty)
        XCTAssertTrue(
            persistence.pendingEvidence(actorID: "act_1", sessionID: "onb_1").isEmpty,
            "Library must be seen after commit rather than replayed from merge selection"
        )
    }

    @MainActor
    func testMergePreviewAdvancesOnlyFromCommittedCardEvidence() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [
            .success(session(state: "product_merge_preview"))
        ]
        service.respondResults = [
            .success(session(state: "product_library_intro"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(3)

        store.receive(.mergeStarted(jobID: "mjob_ready"))
        await settle(2)
        XCTAssertTrue(service.responses.isEmpty)

        store.receive(.mergeCommitted(assetID: "ast_committed"))
        await settle(3)
        XCTAssertEqual(
            service.responses.map(\.input),
            [.choice("activation:merge.committed")]
        )
        XCTAssertEqual(store.session?.state, "product_library_intro")
    }

    @MainActor
    func testCompletionFailureKeepsBuildIgniteRetryable() async {
        let service = MockOnboardingGuideService()
        service.statusResults = [
            .success(status(needs: true, activeSessionID: "onb_1"))
        ]
        service.currentResults = [.success(session(state: "build_ignite"))]
        service.completeResults = [
            .failure(.offline),
            .success(session(status: "completed", state: "completed"))
        ]
        let store = makeStore(service: service)
        store.load(actorID: "act_1")
        await settle(4)

        XCTAssertEqual(store.phase, .active)
        XCTAssertEqual(store.lastError, .offline)
        XCTAssertNotNil(store.guideScene)

        store.retryPendingEvidence()
        await settle(4)

        XCTAssertEqual(service.completedSessionIDs, ["onb_1", "onb_1"])
        XCTAssertEqual(store.phase, .completed)
    }

    @MainActor
    private func makeStore(
        service: MockOnboardingGuideService,
        persistence: OnboardingGuidePersisting = InMemoryOnboardingGuidePersistence()
    ) -> OnboardingGuideStore {
        OnboardingGuideStore(service: service, persistence: persistence)
    }

    private func status(
        needs: Bool,
        activeSessionID: String? = nil
    ) -> OnboardingStatusSnapshot {
        OnboardingStatusSnapshot(
            completed: !needs,
            needsOnboarding: needs,
            latestSessionID: activeSessionID,
            activeSessionID: activeSessionID,
            status: activeSessionID == nil ? nil : "active",
            state: nil
        )
    }

    private func session(
        id: String = "onb_1",
        version: Int = 1,
        status: String = "active",
        state: String
    ) -> OnboardingGuideSession {
        let choices = state == "deepen_signal"
            ? [OnboardingGuideChoice(id: "accurate", label: "Close enough")]
            : []
        return OnboardingGuideSession(
            sessionID: id,
            flowKey: "onboarding_conversation",
            flowVersion: version,
            status: status,
            state: state,
            scene: OnboardingGuideScene(
                speaker: "chora",
                text: "Guide \(state)",
                inputMode: choices.isEmpty ? "choice" : "choice_or_text",
                choices: choices,
                canSkip: true,
                nextRoute: "explore",
                presentation: "guide_overlay",
                targetAnchor: nil,
                placement: nil,
                spotlight: false,
                choraMode: "guide"
            )
        )
    }

    private func settle(_ turns: Int) async {
        for _ in 0..<turns {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }
}
