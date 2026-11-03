import XCTest
@testable import CoreFlow

@MainActor
final class MergeSessionStoreCommitTests: XCTestCase {
    func testCommitWaitsForDraftSaveAndUsesItsExactAcknowledgedRevisionAndHash() async {
        let service = ControlledDraftMergeService(initialArtifact: makeMergeArtifact())
        let saveResponse = ControlledDraftSaveResponse(
            result: .success(
                MergeArtifactSaveResult(
                    artifactID: "artifact_1",
                    revision: 2,
                    documentHash: "sha256:saved-exact-2",
                    presentationHash: "sha256:presentation-2",
                    presentation: MergeArtifactPresentation(
                        schemaVersion: "merge_artifact_presentation.v1",
                        tags: ["Edited"],
                        rate: 3
                    )
                )
            )
        )
        await service.enqueueSave(saveResponse)
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        let edited = Data(
            #"{"blocks":[{"content":[{"text":"Edited","type":"text"}],"id":"blk_edited","type":"paragraph"}],"meta":{},"schemaVersion":"card_doc.v1"}"#.utf8
        )
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["save-key", "commit-key"]
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }
        store.updateArtifactDraft(
            documentJSON: edited,
            preservationManifest: Data("manifest-edited".utf8)
        )
        await waitForControlledDraftSave(saveResponse)
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?
                .artifactDraft?.pendingSave?.idempotencyKey,
            "save-key"
        )

        store.commit()
        await Task.yield()
        let callsBeforeSaveAcknowledgement = await service.commitCalls
        XCTAssertTrue(callsBeforeSaveAcknowledgement.isEmpty)
        XCTAssertNil(persistence.snapshot(actorID: "actor_1")?.commitRequest)

        await saveResponse.resume()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].request.idempotencyKey, "commit-key")
        XCTAssertEqual(calls[0].request.revision, 2)
        XCTAssertEqual(calls[0].request.artifactHash, "sha256:saved-exact-2")
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?.commitRequest,
            calls[0].request
        )
    }

    func testMutationObservedAfterFirstFlushAcknowledgementIsSavedBeforeCommit() async {
        let service = ControlledDraftMergeService(initialArtifact: makeMergeArtifact())
        let firstResponse = ControlledDraftSaveResponse(
            result: .success(draftSaveResult(revision: 2, tags: ["First"]))
        )
        let secondResponse = ControlledDraftSaveResponse(
            result: .success(draftSaveResult(revision: 3, tags: ["Second"]))
        )
        await service.enqueueSave(firstResponse)
        await service.enqueueSave(secondResponse)
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["save-first", "save-second", "commit-exact"]
        )
        var didInjectMutation = false
        persistence.onSave = { snapshot in
            guard !didInjectMutation,
                  snapshot.artifactDraft?.baseRevision == 2,
                  snapshot.artifactDraft?.pendingSave == nil else { return }
            didInjectMutation = true
            store.updateArtifactTags(["Second"])
        }
        store.start()
        await waitForMergeStore { store.phase == .ready }
        store.updateArtifactTags(["First"])
        await waitForControlledDraftSave(firstResponse)

        store.commit()
        await firstResponse.resume()
        await waitForControlledDraftSave(secondResponse)
        let callsBeforeSecondAcknowledgement = await service.commitCalls
        XCTAssertTrue(callsBeforeSecondAcknowledgement.isEmpty)

        await secondResponse.resume()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let saveCalls = await service.saveCalls
        let commitCalls = await service.commitCalls
        XCTAssertTrue(didInjectMutation)
        XCTAssertEqual(saveCalls.map(\.request.idempotencyKey), ["save-first", "save-second"])
        XCTAssertEqual(commitCalls.count, 1)
        guard saveCalls.count == 2, commitCalls.count == 1 else { return }
        XCTAssertEqual(saveCalls[1].request.baseRevision, 2)
        XCTAssertEqual(saveCalls[1].request.tags, ["Second"])
        XCTAssertEqual(commitCalls[0].request.revision, 3)
        XCTAssertEqual(commitCalls[0].request.artifactHash, "sha256:document-3")
    }

    func testUnsyncedDraftFailurePreventsCommitAndKeepsExactPendingOperation() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["save-stable", "must-not-commit"]
        )
        await service.enqueueSave(.failure(.timeout))
        await service.enqueueSave(.failure(.timeout))
        store.updateArtifactTags(["Unsynced"])
        do {
            _ = try await store.flushArtifactDraft()
            XCTFail("Expected the initial draft save to time out")
        } catch {
            XCTAssertEqual(error as? CoreMergeError, .timeout)
        }
        XCTAssertEqual(store.artifactDraftSyncState, .unsynced(.timeout))
        let pendingBeforeAccept = store.artifactDraft?.pendingSave

        store.commit()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while true {
            let saveCallCount = await service.saveCalls.count
            if saveCallCount >= 2,
               store.artifactActionError == .timeout,
               !store.isOperationInFlight {
                break
            }
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the commit-triggered draft retry")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(store.phase, .ready)
        let commitCalls = await service.commitCalls
        XCTAssertTrue(commitCalls.isEmpty)
        XCTAssertNil(store.activeSnapshot?.commitRequest)
        XCTAssertEqual(store.artifactDraft?.pendingSave, pendingBeforeAccept)
        let saveCalls = await service.saveCalls
        XCTAssertEqual(saveCalls.count, 2)
        guard saveCalls.count == 2 else { return }
        XCTAssertEqual(saveCalls[0].request, saveCalls[1].request)
    }

    func testOfflineCommitDoesNotAttemptSaveOrCommitAndKeepsDraftReady() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["save-offline", "must-not-commit"]
        )
        store.setNetworkAvailable(false)
        store.updateArtifactTags(["Offline edit"])
        await waitForMergeStore {
            store.artifactDraftSyncState == .unsynced(.offline)
        }

        store.commit()
        await waitForMergeStore {
            store.artifactActionError == .offline && !store.isOperationInFlight
        }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.artifactDraftSyncState, .unsynced(.offline))
        XCTAssertEqual(store.artifactDraft?.pendingSave?.idempotencyKey, "save-offline")
        let saveCalls = await service.saveCalls
        let commitCalls = await service.commitCalls
        XCTAssertTrue(saveCalls.isEmpty)
        XCTAssertTrue(commitCalls.isEmpty)
    }

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
        XCTAssertEqual(calls[0].request.revision, 1)
        XCTAssertEqual(calls[0].request.artifactHash, "sha256:artifact-document-1")
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
        let expectedArtifact = store.artifact
        store.commit()
        await waitForMergeStore { store.artifactActionError == .offline }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.artifact, expectedArtifact)
        XCTAssertNotNil(store.activeSnapshot?.commitRequest)

        store.commit()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].request, calls[1].request)
        XCTAssertEqual(calls[1].request.idempotencyKey, "commit-stable")
        XCTAssertNil(calls[1].request.target.titleOverride)
    }

    func testPersistedExactCommitSelectionIsNotReplacedByDifferentLoadedArtifact() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        var snapshot = makeMergeSnapshot(jobID: "job_1", status: .artifactReady)
        snapshot.commitRequest = MergeCommitRequest(
            idempotencyKey: "commit-exact",
            revision: 7,
            artifactHash: "sha256:artifact-exact-7",
            target: .newCard(spaceID: nil, titleOverride: nil)
        )
        persistence.seed(snapshot)
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(
            .success(makeMergeArtifact())
        )
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["must-not-be-used"]
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }

        store.commit()
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let calls = await service.commitCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].request.idempotencyKey, "commit-exact")
        XCTAssertEqual(calls[0].request.revision, 7)
        XCTAssertEqual(calls[0].request.artifactHash, "sha256:artifact-exact-7")
    }

    func testPartialLegacyCommitSelectionFailsDecodeWithoutFreshArtifactSelection() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        var snapshot = makeMergeSnapshot(jobID: "job_1", status: .artifactReady)
        snapshot.commitRequest = MergeCommitRequest(
            idempotencyKey: "commit-partial",
            revision: 1,
            artifactHash: nil,
            target: .newCard(spaceID: nil, titleOverride: nil)
        )
        persistence.seed(snapshot)
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        await service.enqueueCommit(.success(makeMergeCommitResult()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["must-not-be-used"]
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }

        store.retry()
        await waitForMergeStore {
            store.phase == .ready
                && store.artifactActionError == .decoding
                && !store.isOperationInFlight
        }

        let commitCalls = await service.commitCalls
        let artifactCalls = await service.artifactCalls
        XCTAssertTrue(commitCalls.isEmpty)
        XCTAssertEqual(artifactCalls, ["job_1"])
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?.commitRequest,
            snapshot.commitRequest
        )
    }

    func testIncompleteCommitResultKeepsArtifactVisibleAndRetryable() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: ["commit-stable"]
        )
        let expectedArtifact = store.artifact
        await service.enqueueCommit(
            .success(
                makeMergeCommitResult(
                    assetID: nil,
                    errorCode: "commit_result_incomplete"
                )
            )
        )

        store.commit()
        await waitForMergeStore {
            store.artifactActionError
                == .server(code: "commit_result_incomplete")
        }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.artifact, expectedArtifact)
        XCTAssertNotNil(store.activeSnapshot?.commitRequest)
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
        await waitForMergeStore { !store.isOperationInFlight }
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
        await service.enqueueArtifact(.success(makeMergeArtifact()))
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
        XCTAssertEqual(calls[0].request.idempotencyKey, commitRequest.idempotencyKey)
        XCTAssertEqual(calls[0].request.target, commitRequest.target)
        XCTAssertEqual(calls[0].request.revision, 1)
        XCTAssertEqual(calls[0].request.artifactHash, "sha256:artifact-document-1")
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?.commitRequest,
            calls[0].request
        )
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
        service: any CoreMergeServing,
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

    private func draftSaveResult(
        revision: Int,
        tags: [String]
    ) -> MergeArtifactSaveResult {
        MergeArtifactSaveResult(
            artifactID: "artifact_1",
            revision: revision,
            documentHash: "sha256:document-\(revision)",
            presentationHash: "sha256:presentation-\(revision)",
            presentation: MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: tags,
                rate: 1
            )
        )
    }
}
