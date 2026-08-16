import XCTest
@testable import CoreFlow

@MainActor
final class MergeSessionStoreArtifactTests: XCTestCase {
    func testArtifactDoesNotExposeLegacyTitleAsCommitInput() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence
        )

        XCTAssertNil(store.activeSnapshot?.commitRequest)
    }

    func testArtifactMismatchFailsWithoutClearingRecoverableSnapshot() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(
            .success(makeMergeArtifact(jobID: "job_other"))
        )
        let store = makeStore(service: service, persistence: persistence)

        store.start()
        await waitForMergeStore { store.phase == .failed(.decoding) }

        XCTAssertNotNil(persistence.snapshot(actorID: "actor_1"))
        XCTAssertTrue(persistence.removals.isEmpty)
    }

    func testDiscardReadyArtifactEndsOnlyThatTask() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(service: service, persistence: persistence)
        await service.enqueueCancel(.success(makeMergeJob(status: .cancelled)))

        store.discardArtifact()
        await waitForMergeStore { store.phase == .cancelled }

        XCTAssertNil(persistence.snapshot(actorID: "actor_1"))
        XCTAssertNil(store.job)
        XCTAssertNil(store.artifact)
    }

    func testDiscardFailureKeepsArtifactVisibleWithInlineError() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(service: service, persistence: persistence)
        let expectedArtifact = store.artifact
        await service.enqueueCancel(.failure(.offline))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))

        store.discardArtifact()
        await waitForMergeStore { store.artifactActionError == .offline }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.artifact, expectedArtifact)
        XCTAssertNotNil(persistence.snapshot(actorID: "actor_1"))
    }

    func testCancelRemovesSnapshotOnlyAfterCanonicalCancelledResponse() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let events = LockedMergeEventLog()
        persistence.onRemove = { _ in events.append("remove") }
        await service.setCancelObserver { _ in events.append("cancel") }
        let store = await readyStore(service: service, persistence: persistence)
        events.removeAll()
        await service.enqueueCancel(.success(makeMergeJob(status: .cancelled)))

        store.cancel()
        XCTAssertNotNil(persistence.snapshot(actorID: "actor_1"))
        await waitForMergeStore { store.phase == .cancelled }

        XCTAssertEqual(events.events, ["cancel", "remove"])
        XCTAssertNil(persistence.snapshot(actorID: "actor_1"))
    }

    func testAmbiguousCancelReconcilesCanonicalReadyState() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(service: service, persistence: persistence)
        await service.enqueueCancel(.failure(.conflict(code: "state_changed")))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))

        store.cancel()
        await waitForMergeStore { store.phase == .ready }

        let cancelCalls = await service.cancelCalls
        let jobCalls = await service.jobCalls
        XCTAssertEqual(cancelCalls, ["job_1"])
        XCTAssertEqual(jobCalls.last, "job_1")
        XCTAssertNotNil(persistence.snapshot(actorID: "actor_1"))
    }

    func testCommittingJobCannotBeCancelled() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        var snapshot = makeMergeSnapshot(jobID: "job_1", status: .committing)
        snapshot.commitRequest = MergeCommitRequest(
            idempotencyKey: "commit-existing",
            target: .newCard(spaceID: nil, titleOverride: nil)
        )
        persistence.seed(snapshot)
        await service.enqueueJob(.success(makeMergeJob(status: .committing)))
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

        store.cancel()

        let cancelCalls = await service.cancelCalls
        XCTAssertTrue(cancelCalls.isEmpty)
        store.suspend(reason: .interrupted)
        await sleeper.resumeNext()
    }

    private func readyStore(
        service: MockCoreMergeService,
        persistence: InMemoryMergeSessionPersistence
    ) async -> MergeSessionStore {
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = makeStore(service: service, persistence: persistence)
        store.start()
        await waitForMergeStore { store.phase == .ready }
        return store
    }

    private func makeStore(
        service: MockCoreMergeService,
        persistence: InMemoryMergeSessionPersistence,
        sleeper: any MergeSleeping = ImmediateMergeSleeper()
    ) -> MergeSessionStore {
        MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            idempotencyKey: { "unused" },
            pollDelaysNanoseconds: [0],
            maxPollAttempts: 3
        )
    }
}
