import XCTest
@testable import CoreFlow

@MainActor
final class MergeSessionStoreCommitTests: XCTestCase {
    func testCompletionAcknowledgementClearsPersistedRecoveryOnce() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["commit-stable"]
        )
        await service.enqueueCommit(.success(makeMergeCommitResult()))

        store.commit()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }
        XCTAssertNotNil(persistence.snapshot(actorID: "actor_1"))

        store.acknowledgeCompletion()
        store.acknowledgeCompletion()

        XCTAssertNil(persistence.snapshot(actorID: "actor_1"))
        XCTAssertEqual(persistence.removals, ["actor_1"])
    }

    func testCommitPersistsStableTitlelessRequestBeforeOneServiceCall() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let events = LockedMergeEventLog()
        persistence.onSave = { _ in events.append("save") }
        await service.setCommitObserver { _, _ in events.append("commit") }
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["commit-stable"]
        )
        events.removeAll()
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        store.commit()
        store.commit()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].request.idempotencyKey, "commit-stable")
        XCTAssertNil(calls[0].request.target.titleOverride)
        XCTAssertEqual(events.events.first, "save")
        XCTAssertEqual(events.events.filter { $0 == "commit" }.count, 1)
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?.committedAssetID,
            "ast_committed"
        )
    }

    func testCommitAlwaysUsesTitlelessVNextTarget() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["commit-stable"]
        )
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        store.commit()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertNil(calls.first?.request.target.titleOverride)
    }

    func testCommitTransportRetryUsesExactPersistedKeyAndTarget() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["commit-stable", "must-not-be-used"]
        )
        await service.enqueueCommit(.failure(.offline))
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        store.commit()
        await waitForMergeStore { store.phase == .paused(.offline) }
        store.retry()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].request, calls[1].request)
        XCTAssertEqual(calls[1].request.idempotencyKey, "commit-stable")
        XCTAssertNil(calls[1].request.target.titleOverride)
    }

    func testCommitConflictReconcilesReadyAndKeepsSameRequestForRetry() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["commit-stable"]
        )
        await service.enqueueCommit(.failure(.conflict(code: "repair_required")))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        store.commit()
        await waitForMergeStore { store.phase == .ready }
        store.retry()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].request, calls[1].request)
    }

    func testCommittedCardRelaunchReplaysSameCommitToRecoverAssetID() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        var snapshot = makeMergeSnapshot(
            jobID: "job_1",
            status: .committing,
            createKey: "create-existing"
        )
        let commitRequest = MergeCommitRequest(
            idempotencyKey: "commit-existing",
            target: .newCard(spaceID: nil, titleOverride: "Recovered")
        )
        snapshot.commitRequest = commitRequest
        persistence.seed(snapshot)
        await service.enqueueJob(.success(makeMergeJob(status: .committedCard)))
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["must-not-be-used"]
        )

        store.start()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].request, commitRequest)
    }

    func testGenerationRetryKeepsSourcesButPersistsNewCreateKey() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let original = makeMergeSnapshot(
            jobID: "job_failed",
            status: .failed,
            createKey: "create-old"
        )
        persistence.seed(original)
        await service.enqueueJob(
            .success(makeMergeJob(id: "job_failed", status: .failed))
        )
        await service.enqueueCreate(
            .success(
                makeMergeJob(
                    id: "job_new",
                    status: .artifactReady,
                    artifactID: "artifact_new"
                )
            )
        )
        await service.enqueueArtifact(
            .success(makeMergeArtifact(jobID: "job_new", artifactID: "artifact_new"))
        )
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["create-new"]
        )
        store.start()
        await waitForMergeStore { store.phase == .failed(.server(code: nil)) }

        store.retryGeneration()
        await waitForMergeStore { store.phase == .ready }

        let calls = await service.createCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].sources, original.createRequest.sources)
        XCTAssertEqual(calls[0].idempotencyKey, "create-new")
        XCTAssertNotEqual(calls[0].idempotencyKey, original.createRequest.idempotencyKey)
        XCTAssertEqual(store.job?.jobID, "job_new")
    }

    func testGenericRetryReplacesDurablyFailedGeneration() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let original = makeMergeSnapshot(
            jobID: "job_failed",
            status: .failed,
            createKey: "create-old"
        )
        persistence.seed(original)
        await service.enqueueJob(
            .success(makeMergeJob(id: "job_failed", status: .failed))
        )
        await service.enqueueCreate(
            .success(
                makeMergeJob(
                    id: "job_new",
                    status: .artifactReady,
                    artifactID: "artifact_new"
                )
            )
        )
        await service.enqueueArtifact(
            .success(
                makeMergeArtifact(
                    jobID: "job_new",
                    artifactID: "artifact_new"
                )
            )
        )
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["create-new"]
        )
        store.start()
        await waitForMergeStore { store.phase == .failed(.server(code: nil)) }

        store.retry()
        await waitForMergeStore { store.phase == .ready }

        let calls = await service.createCalls
        XCTAssertEqual(calls.map(\.idempotencyKey), ["create-new"])
        XCTAssertEqual(calls.first?.sources, original.createRequest.sources)
        XCTAssertEqual(store.job?.jobID, "job_new")
    }

    private func readyStore(
        service: MockCoreMergeService,
        persistence: InMemoryMergeSessionPersistence,
        keys: [String]
    ) async -> MergeSessionStore {
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: keys
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }
        return store
    }

    private func makeStore(
        service: MockCoreMergeService,
        persistence: InMemoryMergeSessionPersistence,
        keys: [String]
    ) -> MergeSessionStore {
        var remainingKeys = keys
        return MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: ImmediateMergeSleeper(),
            idempotencyKey: { remainingKeys.removeFirst() },
            pollDelaysNanoseconds: [0],
            maxPollAttempts: 3
        )
    }
}
