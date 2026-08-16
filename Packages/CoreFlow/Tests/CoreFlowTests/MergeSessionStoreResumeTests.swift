import XCTest
@testable import CoreFlow

@MainActor
final class MergeSessionStoreResumeTests: XCTestCase {
    func testPendingCreateRelaunchReplaysExactPersistedRequest() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let snapshot = makeMergeSnapshot(createKey: "create-existing")
        persistence.seed(snapshot)
        await service.enqueueCreate(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = makeStore(service: service, persistence: persistence)

        store.start()
        await waitForMergeStore { store.phase == .ready }

        let calls = await service.createCalls
        XCTAssertEqual(calls, [snapshot.createRequest])
        XCTAssertEqual(store.selectedSources, snapshot.createRequest.sources)
    }

    func testRunningJobPollsUntilArtifactReady() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(
            makeMergeSnapshot(
                jobID: "job_1",
                status: .created
            )
        )
        await service.enqueueJob(.success(makeMergeJob(status: .snapshotReady)))
        await service.enqueueJob(.success(makeMergeJob(status: .generating)))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let sleeper = ImmediateMergeSleeper()
        let store = makeStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper
        )

        store.start()
        await waitForMergeStore { store.phase == .ready }

        let jobCalls = await service.jobCalls
        let sleepCalls = await sleeper.calls
        XCTAssertEqual(jobCalls, ["job_1", "job_1", "job_1"])
        XCTAssertEqual(sleepCalls.count, 2)
        XCTAssertEqual(store.job?.status, .artifactReady)
        XCTAssertEqual(store.artifact?.artifactID, "artifact_1")
    }

    func testDefaultPollBudgetCoversLongestThreeProviderRoute() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(
            makeMergeSnapshot(jobID: "job_1", status: .generating)
        )
        for _ in 0..<160 {
            await service.enqueueJob(
                .success(makeMergeJob(status: .generating))
            )
        }
        await service.enqueueJob(
            .success(
                makeMergeJob(
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: ImmediateMergeSleeper(),
            idempotencyKey: { "must-not-create-a-new-key" },
            pollDelaysNanoseconds: [0],
            pollDelayJitter: { $0 }
        )

        store.start()
        await waitForMergeStore { store.phase == .ready }

        let jobCalls = await service.jobCalls
        XCTAssertEqual(jobCalls.count, 161)
        XCTAssertEqual(store.artifact?.artifactID, "artifact_1")
    }

    func testFreshEntryStartsSelectionInsteadOfRestoringFailedSession() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(
            makeMergeSnapshot(jobID: "job_failed", status: .failed)
        )
        await service.enqueueCapabilities(
            .success([makeMergeCapability()])
        )
        let incomingAnchor = makeMergeSource(
            "ast_anchor",
            preview: "Current anchor"
        )
        let store = MergeSessionStore(
            actorID: "actor_1",
            anchor: incomingAnchor,
            service: service,
            persistence: persistence,
            sleeper: ImmediateMergeSleeper(),
            resumePersistedSession: false,
            pollDelaysNanoseconds: [0],
            pollDelayJitter: { $0 }
        )

        store.start()
        await waitForMergeStore { store.phase == .selection }

        XCTAssertEqual(store.selectedSources, [incomingAnchor])
        XCTAssertNil(store.activeSnapshot)
    }

    func testPollBudgetPausesWithoutChangingCanonicalJobToFailed() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .generating))
        await service.enqueueJob(.success(makeMergeJob(status: .generating)))
        await service.enqueueJob(.success(makeMergeJob(status: .generating)))
        await service.enqueueJob(.success(makeMergeJob(status: .generating)))
        let store = makeStore(
            service: service,
            persistence: persistence,
            maxPollAttempts: 2
        )

        store.start()
        await waitForMergeStore { store.phase == .paused(.timeout) }

        XCTAssertEqual(store.job?.status, .generating)
        XCTAssertEqual(persistence.snapshot(actorID: "actor_1")?.jobID, "job_1")
        XCTAssertTrue(persistence.removals.isEmpty)
    }

    func testCanonicalCancelledClearsOnlyAfterObservation() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .generating))
        await service.enqueueJob(.success(makeMergeJob(status: .cancelled)))
        let store = makeStore(service: service, persistence: persistence)

        store.start()
        await waitForMergeStore { store.phase == .cancelled }

        XCTAssertEqual(persistence.removals, ["actor_1"])
        XCTAssertNil(persistence.snapshot(actorID: "actor_1"))
    }

    func testCanonicalFailureKeepsSourcesForExplicitRetry() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let snapshot = makeMergeSnapshot(jobID: "job_1", status: .generating)
        persistence.seed(snapshot)
        await service.enqueueJob(
            .success(makeMergeJob(status: .failed, errorCode: "generation_failed"))
        )
        let store = makeStore(service: service, persistence: persistence)

        store.start()
        await waitForMergeStore {
            store.phase == .failed(.server(code: "generation_failed"))
        }

        XCTAssertEqual(store.selectedSources, snapshot.createRequest.sources)
        XCTAssertEqual(persistence.snapshot(actorID: "actor_1")?.jobID, "job_1")
    }

    func testSuspendCancelsFuturePollWithoutRewritingCanonicalPhase() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .created))
        await service.enqueueJob(.success(makeMergeJob(status: .generating)))
        let sleeper = ControlledMergeSleeper()
        let store = makeStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper
        )

        store.start()
        for _ in 0..<500 where await sleeper.pendingCount == 0 {
            await Task.yield()
        }
        let pendingCount = await sleeper.pendingCount
        XCTAssertEqual(pendingCount, 1)
        XCTAssertEqual(store.phase, .weaving(.generating))

        store.suspend(reason: nil)
        await sleeper.resumeNext()
        await Task.yield()

        XCTAssertEqual(store.phase, .weaving(.generating))
        XCTAssertEqual(persistence.snapshot(actorID: "actor_1")?.jobID, "job_1")
        let jobCalls = await service.jobCalls
        XCTAssertEqual(jobCalls, ["job_1"])
    }

    func testCancelledStaleJobResponseCannotOverwriteNewerReconcile() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .created))
        let stale = await service.enqueueControlledJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "stale_artifact"
                )
            )
        )
        let sleeper = ControlledMergeSleeper()
        let store = makeStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper
        )
        store.start()
        await waitForControlledJob(stale)

        store.suspend(reason: nil)
        await service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .generating))
        )
        await service.enqueueArtifact(
            jobID: "job_1",
            .success(
                makeMergeArtifact(
                    jobID: "job_1",
                    artifactID: "stale_artifact"
                )
            )
        )
        store.resume()
        await waitForMergeStore { store.phase == .weaving(.generating) }
        XCTAssertEqual(store.statusResponseCount, 1)

        await stale.resume()
        await waitForMergeStore {
            store.cancelledStatusResponseDiscardCount == 1
        }

        XCTAssertEqual(store.statusResponseCount, 2)
        XCTAssertEqual(store.phase, .weaving(.generating))
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?.lastStatus,
            .generating
        )
        store.suspend(reason: nil)
        await sleeper.resumeNext()
    }

    func testPollDelayJitterPreservesZeroAtUpperFactor() {
        XCTAssertEqual(
            MergePollDelayJitter.applying(to: 0, factor: 1.15),
            0
        )
    }

    func testPollDelayJitterAppliesExactProductionFactorBounds() {
        XCTAssertEqual(
            MergePollDelayJitter.applying(to: 1_000, factor: 0.85),
            850
        )
        XCTAssertEqual(
            MergePollDelayJitter.applying(to: 1_000, factor: 1.15),
            1_150
        )
    }

    func testInjectedPollDelayJitterReachesSleeper() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .generating))
        await service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .generating))
        )
        let sleeper = ControlledMergeSleeper()
        let store = MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            idempotencyKey: { "must-not-create-a-new-key" },
            pollDelaysNanoseconds: [1_000],
            pollDelayJitter: { $0 + 137 },
            maxPollAttempts: 1
        )

        store.start()
        await waitForPendingSleep(sleeper)

        let sleepCalls = await sleeper.calls
        XCTAssertEqual(sleepCalls, [1_137])
        store.suspend(reason: nil)
        await sleeper.resumeNext()
    }

    private func makeStore(
        service: MockCoreMergeService,
        persistence: InMemoryMergeSessionPersistence,
        sleeper: any MergeSleeping = ImmediateMergeSleeper(),
        maxPollAttempts: Int = 4
    ) -> MergeSessionStore {
        MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            idempotencyKey: { "must-not-create-a-new-key" },
            pollDelaysNanoseconds: [0],
            pollDelayJitter: { $0 },
            maxPollAttempts: maxPollAttempts
        )
    }
}

private func waitForPendingSleep(
    _ sleeper: ControlledMergeSleeper,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await sleeper.pendingCount > 0 { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for Merge poll sleep")
}
