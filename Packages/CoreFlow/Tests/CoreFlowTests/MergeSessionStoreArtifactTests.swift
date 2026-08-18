import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class MergeSessionStoreArtifactTests: XCTestCase {
    func testThreeRapidDraftMutationsDebounceIntoOneLatestNormalizedSave() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let sleeper = ControlledMergeSleeper()
        let keys = MergeKeySequence(["save-one"])
        let store = await readyStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            keys: keys
        )
        await service.enqueueSave(.success(saveResult(revision: 2)))
        let first = document(id: "blk_first", text: "First")
        let latest = document(id: "blk_latest", text: "Latest")

        store.updateArtifactDraft(
            documentJSON: first,
            preservationManifest: Data("manifest-first".utf8)
        )
        store.updateArtifactTags([" #Design ", "Design", "Research", " "])
        store.updateArtifactDraft(
            documentJSON: latest,
            preservationManifest: Data("manifest-latest".utf8)
        )

        await waitForPendingDraftSleep(sleeper)
        let sleepCalls = await sleeper.calls
        let callsBeforeDebounce = await service.saveCalls
        XCTAssertFalse(sleepCalls.isEmpty)
        XCTAssertTrue(sleepCalls.allSatisfy { $0 == 600_000_000 })
        XCTAssertTrue(callsBeforeDebounce.isEmpty)
        while await sleeper.pendingCount > 0 {
            await sleeper.resumeNext()
        }
        await waitForMergeStore { store.artifactDraftSyncState == .clean }

        let calls = await service.saveCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].request.documentJSON, latest)
        XCTAssertEqual(calls[0].request.tags, ["Design", "Research"])
        XCTAssertEqual(calls[0].request.idempotencyKey, "save-one")
        XCTAssertEqual(store.phase, .ready)
    }

    func testMutationDuringSaveCreatesSecondOperationFromAcknowledgedRevision() async {
        let initial = draftArtifact(revision: 1)
        let service = ControlledDraftMergeService(initialArtifact: initial)
        let firstResponse = ControlledDraftSaveResponse(
            result: .success(saveResult(revision: 2))
        )
        let secondResponse = ControlledDraftSaveResponse(
            result: .success(saveResult(revision: 3))
        )
        await service.enqueueSave(firstResponse)
        await service.enqueueSave(secondResponse)
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-first", "save-second"])
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }

        store.updateArtifactDraft(
            documentJSON: document(id: "blk_first", text: "First"),
            preservationManifest: Data("manifest-first".utf8)
        )
        await waitForControlledDraftSave(firstResponse)
        store.updateArtifactDraft(
            documentJSON: document(id: "blk_second", text: "Second"),
            preservationManifest: Data("manifest-second".utf8)
        )

        await firstResponse.resume()
        await waitForControlledDraftSave(secondResponse)
        let callsAfterAcknowledgement = await service.saveCalls
        XCTAssertEqual(callsAfterAcknowledgement.count, 2)
        XCTAssertEqual(callsAfterAcknowledgement[0].request.baseRevision, 1)
        XCTAssertEqual(callsAfterAcknowledgement[0].request.idempotencyKey, "save-first")
        XCTAssertEqual(callsAfterAcknowledgement[1].request.baseRevision, 2)
        XCTAssertEqual(callsAfterAcknowledgement[1].request.baseHash, "sha256:document-2")
        XCTAssertEqual(callsAfterAcknowledgement[1].request.idempotencyKey, "save-second")
        XCTAssertEqual(
            callsAfterAcknowledgement[1].request.documentJSON,
            document(id: "blk_second", text: "Second")
        )

        await secondResponse.resume()
        await waitForMergeStore { store.artifactDraftSyncState == .clean }
        XCTAssertEqual(store.artifact?.latestRevision, 3)
        XCTAssertEqual(store.phase, .ready)
    }

    func testValidationAfterCorrectedMutationCreatesReplacementAndCommitWaits() async {
        let initial = draftArtifact(revision: 1)
        let service = ControlledDraftMergeService(initialArtifact: initial)
        let rejectedResponse = ControlledDraftSaveResponse(
            result: .failure(.validation(code: "invalid_document"))
        )
        let correctedResponse = ControlledDraftSaveResponse(
            result: .success(saveResult(revision: 2, tags: ["Corrected"]))
        )
        await service.enqueueSave(rejectedResponse)
        await service.enqueueSave(correctedResponse)
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-p1", "save-p2", "commit-after-p2"])
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }
        let rejectedDocument = document(id: "blk_p1", text: "Rejected")
        store.updateArtifactDraft(
            documentJSON: rejectedDocument,
            preservationManifest: Data("manifest-p1".utf8)
        )
        store.updateArtifactTags(["Rejected"])
        await waitForControlledDraftSave(rejectedResponse)

        store.commit()
        XCTAssertTrue(store.isOperationInFlight)
        let correctedDocument = document(id: "blk_p2", text: "Corrected")
        store.updateArtifactDraft(
            documentJSON: correctedDocument,
            preservationManifest: Data("manifest-p2".utf8)
        )
        store.updateArtifactTags(["Corrected"])
        await rejectedResponse.resume()
        await waitForControlledDraftSave(correctedResponse)

        let callsBeforeAcknowledgement = await service.saveCalls
        XCTAssertEqual(callsBeforeAcknowledgement.count, 2)
        XCTAssertEqual(
            callsBeforeAcknowledgement.map(\.request.idempotencyKey),
            ["save-p1", "save-p2"]
        )
        XCTAssertEqual(
            callsBeforeAcknowledgement.last?.request.baseRevision,
            callsBeforeAcknowledgement.first?.request.baseRevision
        )
        XCTAssertEqual(
            callsBeforeAcknowledgement.last?.request.baseHash,
            callsBeforeAcknowledgement.first?.request.baseHash
        )
        XCTAssertEqual(
            callsBeforeAcknowledgement.last?.request.documentJSON,
            correctedDocument
        )
        XCTAssertEqual(
            callsBeforeAcknowledgement.last?.request.tags,
            ["Corrected"]
        )
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?
                .artifactDraft?.pendingSave?.idempotencyKey,
            "save-p2"
        )

        if await correctedResponse.isWaiting {
            await correctedResponse.resume()
        }
        await waitForMergeStore {
            store.phase == .completed(assetID: "ast_committed")
        }

        let commits = await service.commitCalls
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.request.idempotencyKey, "commit-after-p2")
        XCTAssertEqual(commits.first?.request.revision, 2)
        XCTAssertEqual(commits.first?.request.artifactHash, "sha256:document-2")
    }

    func testConcurrentFlushWaitersShareEachSaveAndSerializeNewerMutation() async {
        let service = ControlledDraftMergeService(initialArtifact: draftArtifact(revision: 1))
        let firstResponse = ControlledDraftSaveResponse(
            result: .success(saveResult(revision: 2))
        )
        let secondResponse = ControlledDraftSaveResponse(
            result: .success(saveResult(revision: 3))
        )
        await service.enqueueSave(firstResponse)
        await service.enqueueSave(secondResponse)
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-first", "save-second"])
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }

        store.updateArtifactDraft(
            documentJSON: document(id: "blk_first", text: "First"),
            preservationManifest: Data("manifest-first".utf8)
        )
        await waitForControlledDraftSave(firstResponse)
        store.updateArtifactDraft(
            documentJSON: document(id: "blk_second", text: "Second"),
            preservationManifest: Data("manifest-second".utf8)
        )
        let firstFlush = Task { @MainActor in
            try await store.flushArtifactDraft()
        }
        let secondFlush = Task { @MainActor in
            try await store.flushArtifactDraft()
        }

        await firstResponse.resume()
        await waitForControlledDraftSave(secondResponse)
        await secondResponse.resume()
        _ = try? await firstFlush.value
        _ = try? await secondFlush.value
        await waitForMergeStore { store.artifactDraftSyncState == .clean }

        let calls = await service.saveCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.map(\.request.idempotencyKey), ["save-first", "save-second"])
        XCTAssertEqual(calls[1].request.baseRevision, 2)
        XCTAssertEqual(store.artifact?.latestRevision, 3)
    }

    func testTimeoutRelaunchReplaysExactPersistedBytesAndKey() async {
        let firstService = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let firstStore = await readyStore(
            service: firstService,
            persistence: persistence,
            keys: MergeKeySequence(["save-stable"])
        )
        await firstService.enqueueSave(.failure(.timeout))
        let edited = document(id: "blk_retry", text: "Retry exactly")

        firstStore.updateArtifactDraft(
            documentJSON: edited,
            preservationManifest: Data("manifest-retry".utf8)
        )
        firstStore.updateArtifactTags([" #Retry "])
        await waitForMergeStore {
            firstStore.artifactDraftSyncState == .unsynced(.timeout)
        }
        let firstCalls = await firstService.saveCalls
        let firstCall = try? XCTUnwrap(firstCalls.first)
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?
                .artifactDraft?.pendingSave?.idempotencyKey,
            "save-stable"
        )

        let secondService = MockCoreMergeService()
        await secondService.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await secondService.enqueueArtifact(.success(makeMergeArtifact()))
        await secondService.enqueueSave(.success(saveResult(revision: 2)))
        let relaunched = makeStore(
            service: secondService,
            persistence: persistence,
            keys: MergeKeySequence(["must-not-be-used"])
        )

        relaunched.start()
        await waitForMergeStore { relaunched.artifactDraftSyncState == .clean }

        let replayCalls = await secondService.saveCalls
        let replay = try? XCTUnwrap(replayCalls.first)
        XCTAssertEqual(replay?.request, firstCall?.request)
        XCTAssertEqual(replay?.request.documentJSON, edited)
        XCTAssertEqual(replay?.request.tags, ["Retry"])
        XCTAssertEqual(replay?.request.idempotencyKey, "save-stable")
    }

    func testValidationRejectedSaveIsReplacedOnlyAfterNewMutation() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-rejected", "save-after-edit"])
        )
        await service.enqueueSave(
            .failure(.validation(code: "invalid_document"))
        )
        let rejectedDocument = document(
            id: "blk_rejected",
            text: "Rejected"
        )

        store.updateArtifactDraft(
            documentJSON: rejectedDocument,
            preservationManifest: Data("manifest-rejected".utf8)
        )
        await waitForMergeStore {
            store.artifactDraftSyncState
                == .unsynced(.validation(code: "invalid_document"))
        }
        for _ in 0..<20 { await Task.yield() }

        let callsWithoutMutation = await service.saveCalls
        XCTAssertEqual(callsWithoutMutation.count, 1)
        XCTAssertEqual(
            callsWithoutMutation.first?.request.idempotencyKey,
            "save-rejected"
        )
        XCTAssertEqual(
            callsWithoutMutation.first?.request.documentJSON,
            rejectedDocument
        )

        await service.enqueueSave(.success(saveResult(revision: 2)))
        // A spare response keeps the pre-fix mutation loop observable instead
        // of terminating the test process on the mock's empty-queue guard.
        await service.enqueueSave(.success(saveResult(revision: 3)))
        let correctedDocument = document(
            id: "blk_corrected",
            text: "Corrected"
        )
        store.updateArtifactDraft(
            documentJSON: correctedDocument,
            preservationManifest: Data("manifest-corrected".utf8)
        )
        store.updateArtifactTags(["Corrected"])
        _ = try? await store.flushArtifactDraft()

        let calls = await service.saveCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].request.idempotencyKey, "save-after-edit")
        XCTAssertNotEqual(
            calls[1].request.idempotencyKey,
            calls[0].request.idempotencyKey
        )
        XCTAssertEqual(
            calls[1].request.baseRevision,
            calls[0].request.baseRevision
        )
        XCTAssertEqual(calls[1].request.baseHash, calls[0].request.baseHash)
        XCTAssertEqual(calls[1].request.documentJSON, correctedDocument)
        XCTAssertEqual(calls[1].request.tags, ["Corrected"])
        XCTAssertEqual(store.artifact?.latestRevision, 2)
        XCTAssertEqual(store.artifactDraftSyncState, .clean)
    }

    func testValidationRejectedSaveDoesNotRetryWithoutNewMutation() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-rejected"])
        )
        await service.enqueueSave(
            .failure(.validation(code: "invalid_document"))
        )
        store.updateArtifactDraft(
            documentJSON: document(id: "blk_rejected", text: "Rejected"),
            preservationManifest: Data("manifest-rejected".utf8)
        )
        await waitForMergeStore {
            store.artifactDraftSyncState
                == .unsynced(.validation(code: "invalid_document"))
        }
        await service.enqueueSave(
            .failure(.server(code: "must_not_be_sent"))
        )

        do {
            _ = try await store.flushArtifactDraft()
            XCTFail("A definitively rejected draft must remain unsynced")
        } catch {
            XCTAssertEqual(
                error as? CoreMergeError,
                .validation(code: "invalid_document")
            )
        }

        let calls = await service.saveCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.request.idempotencyKey, "save-rejected")
        XCTAssertEqual(
            store.artifactDraftSyncState,
            .unsynced(.validation(code: "invalid_document"))
        )
    }

    func testRelaunchReplacesRejectedSaveWhenPersistedDraftIsAlreadyCorrected() async {
        let original = makeMergeArtifact()
        let rejectedDocument = document(id: "blk_p1", text: "Rejected")
        let correctedDocument = document(id: "blk_p2", text: "Corrected")
        let rejectedPending = MergePendingArtifactSave(
            idempotencyKey: "save-p1",
            baseRevision: original.latestRevision,
            baseDocumentHash: original.latestHash,
            documentJSON: rejectedDocument,
            tags: ["Rejected"]
        )
        var snapshot = makeMergeSnapshot(jobID: "job_1", status: .artifactReady)
        snapshot.artifactDraft = MergeArtifactDraftSnapshot(
            baseRevision: original.latestRevision,
            baseDocumentHash: original.latestHash,
            documentJSON: correctedDocument,
            tags: ["Corrected"],
            rate: original.presentation.rate,
            preservationManifest: Data("manifest-p2".utf8),
            pendingSave: rejectedPending,
            validationRejection: MergeArtifactDraftValidationRejection(
                idempotencyKey: rejectedPending.idempotencyKey,
                code: "invalid_document"
            )
        )
        let persistence = InMemoryMergeSessionPersistence()
        persistence.seed(snapshot)
        let service = MockCoreMergeService()
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(original))
        await service.enqueueSave(
            .success(saveResult(revision: 2, tags: ["Corrected"]))
        )
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-p2"])
        )

        store.start()
        await waitForMergeStore {
            store.phase == .ready
                && (
                    store.artifactDraftSyncState == .clean
                        || store.artifactDraftSyncState
                            == .unsynced(.validation(code: "invalid_document"))
                )
        }

        XCTAssertEqual(store.artifactDraftSyncState, .clean)
        let calls = await service.saveCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.request.idempotencyKey, "save-p2")
        XCTAssertEqual(calls.first?.request.baseRevision, original.latestRevision)
        XCTAssertEqual(calls.first?.request.baseHash, original.latestHash)
        XCTAssertEqual(calls.first?.request.documentJSON, correctedDocument)
        XCTAssertEqual(calls.first?.request.tags, ["Corrected"])
        XCTAssertNil(
            persistence.snapshot(actorID: "actor_1")?
                .artifactDraft?.validationRejection
        )
    }

    func testTagOnlyDraftSaveAdvancesRevisionWithoutChangingLifecyclePhase() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-tags"])
        )
        await service.enqueueSave(
            .success(saveResult(revision: 2, tags: ["Design", "Research"]))
        )
        let originalDocument = try? XCTUnwrap(store.artifact?.documentJSON)

        store.updateArtifactTags(["Design", "Research"])
        await waitForMergeStore { store.artifactDraftSyncState == .clean }

        let calls = await service.saveCalls
        let call = try? XCTUnwrap(calls.first)
        XCTAssertEqual(call?.request.documentJSON, originalDocument)
        XCTAssertEqual(call?.request.tags, ["Design", "Research"])
        XCTAssertEqual(store.artifact?.latestRevision, 2)
        XCTAssertEqual(store.artifactDraft?.baseRevision, 2)
        XCTAssertEqual(store.phase, .ready)
    }

    func testDirtyConflictKeepsLocalDraftAndKeepMineRebasesWithNewKey() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let keys = MergeKeySequence(["save-conflicted", "save-rebased"])
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: keys
        )
        let local = document(id: "blk_local", text: "Mine")
        let server = draftArtifact(
            revision: 2,
            documentJSON: document(id: "blk_server", text: "Server"),
            tags: ["Server"]
        )
        await service.enqueueSave(.failure(.conflict(code: "stale_base")))
        await service.enqueueArtifact(.success(server))

        store.updateArtifactDraft(
            documentJSON: local,
            preservationManifest: Data("manifest-local".utf8)
        )
        await waitForMergeStore {
            store.artifactDraftSyncState
                == .conflict(
                    MergeArtifactConflict(
                        serverRevision: 2,
                        serverDocumentHash: "sha256:document-2"
                    )
                )
        }

        XCTAssertEqual(store.artifactDraft?.documentJSON, local)
        XCTAssertEqual(store.phase, .ready)
        await service.enqueueSave(.success(saveResult(revision: 3)))
        await store.resolveArtifactConflict(.keepMine)
        await waitForMergeStore { store.artifactDraftSyncState == .clean }

        let calls = await service.saveCalls
        XCTAssertEqual(calls.map(\.request.idempotencyKey), ["save-conflicted", "save-rebased"])
        XCTAssertEqual(calls[1].request.baseRevision, 2)
        XCTAssertEqual(calls[1].request.baseHash, "sha256:document-2")
        XCTAssertEqual(calls[1].request.documentJSON, local)
    }

    func testDirtyConflictReloadServerAdoptsLatestAndClearsPendingOperation() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["save-conflicted"])
        )
        let serverDocument = document(id: "blk_server", text: "Server")
        let server = draftArtifact(
            revision: 2,
            documentJSON: serverDocument,
            tags: ["Server"],
            rate: 3
        )
        await service.enqueueSave(.failure(.conflict(code: "stale_base")))
        await service.enqueueArtifact(.success(server))
        store.updateArtifactDraft(
            documentJSON: document(id: "blk_local", text: "Mine"),
            preservationManifest: Data("manifest-local".utf8)
        )
        await waitForMergeStore {
            if case .conflict = store.artifactDraftSyncState { return true }
            return false
        }

        await store.resolveArtifactConflict(.reloadServer)

        XCTAssertEqual(store.artifactDraftSyncState, .clean)
        XCTAssertEqual(store.artifactDraft?.documentJSON, serverDocument)
        XCTAssertEqual(store.artifactDraft?.tags, ["Server"])
        XCTAssertEqual(store.artifactDraft?.rate, 3)
        XCTAssertNil(store.artifactDraft?.pendingSave)
        XCTAssertEqual(store.phase, .ready)
    }

    func testCleanConflictAutomaticallyAdoptsServerLatest() async {
        let original = makeMergeArtifact()
        let persistence = InMemoryMergeSessionPersistence()
        var snapshot = makeMergeSnapshot(jobID: "job_1", status: .artifactReady)
        snapshot.artifactDraft = MergeArtifactDraftSnapshot(
            baseRevision: 0,
            baseDocumentHash: "sha256:stale",
            documentJSON: original.documentJSON,
            tags: original.presentation.tags,
            rate: original.presentation.rate,
            preservationManifest: Data("manifest-original".utf8),
            pendingSave: MergePendingArtifactSave(
                idempotencyKey: "save-stale-clean",
                baseRevision: 0,
                baseDocumentHash: "sha256:stale",
                documentJSON: original.documentJSON,
                tags: original.presentation.tags
            )
        )
        persistence.seed(snapshot)
        let service = MockCoreMergeService()
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(original))
        await service.enqueueSave(.failure(.conflict(code: "stale_base")))
        let latest = draftArtifact(
            revision: 2,
            documentJSON: document(id: "blk_server", text: "Server latest"),
            tags: ["Latest"]
        )
        await service.enqueueArtifact(.success(latest))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["must-not-be-used"])
        )

        store.start()
        await waitForMergeStore {
            store.artifactDraftSyncState == .clean
                && store.artifact?.latestRevision == 2
        }

        XCTAssertEqual(store.artifactDraft?.documentJSON, latest.documentJSON)
        XCTAssertEqual(store.artifactDraft?.tags, ["Latest"])
        XCTAssertNil(store.artifactDraft?.pendingSave)
    }

    func testCleanConflictDoesNotAdoptServerOverMutationDuringLatestFetch() async {
        let original = makeMergeArtifact()
        let persistence = InMemoryMergeSessionPersistence()
        var snapshot = makeMergeSnapshot(jobID: "job_1", status: .artifactReady)
        snapshot.artifactDraft = MergeArtifactDraftSnapshot(
            baseRevision: 0,
            baseDocumentHash: "sha256:stale",
            documentJSON: original.documentJSON,
            tags: original.presentation.tags,
            rate: original.presentation.rate,
            preservationManifest: Data("manifest-original".utf8),
            pendingSave: MergePendingArtifactSave(
                idempotencyKey: "save-stale-clean",
                baseRevision: 0,
                baseDocumentHash: "sha256:stale",
                documentJSON: original.documentJSON,
                tags: original.presentation.tags
            )
        )
        persistence.seed(snapshot)
        let service = ControlledDraftMergeService(initialArtifact: original)
        let staleSave = ControlledDraftSaveResponse(
            result: .failure(.conflict(code: "stale_base"))
        )
        await service.enqueueSave(staleSave)
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: MergeKeySequence(["must-not-be-used"])
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }
        await waitForControlledDraftSave(staleSave)

        let latest = draftArtifact(
            revision: 2,
            documentJSON: document(id: "blk_server", text: "Server latest"),
            tags: ["Server"]
        )
        let latestFetch = ControlledDraftArtifactResponse(artifact: latest)
        await service.enqueueArtifact(latestFetch)
        await staleSave.resume()
        await waitForControlledDraftArtifact(latestFetch)

        let localDocument = document(id: "blk_local", text: "Local edit")
        store.updateArtifactDraft(
            documentJSON: localDocument,
            preservationManifest: Data("manifest-local".utf8)
        )
        store.updateArtifactTags(["Local"])
        await latestFetch.resume()
        await waitForMergeStore {
            if case .conflict = store.artifactDraftSyncState { return true }
            return store.artifactDraftSyncState == .clean
                && store.artifact?.latestRevision == 2
        }

        XCTAssertEqual(
            store.artifactDraftSyncState,
            .conflict(
                MergeArtifactConflict(
                    serverRevision: 2,
                    serverDocumentHash: "sha256:document-2"
                )
            )
        )
        XCTAssertEqual(store.artifactDraft?.documentJSON, localDocument)
        XCTAssertEqual(store.artifactDraft?.tags, ["Local"])
        XCTAssertNotNil(store.artifactDraft?.pendingSave)
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?
                .artifactDraft?.documentJSON,
            localDocument
        )
    }

    func testLifetimeInvalidationPreventsLateConflictFetchFromPublishingState() async {
        let original = makeMergeArtifact()
        let latest = draftArtifact(
            revision: 2,
            documentJSON: document(id: "blk_server", text: "Server latest"),
            tags: ["Server"]
        )
        let lateResults: [Result<MergeArtifact, CoreMergeError>] = [
            .success(latest),
            .failure(.timeout)
        ]

        for lateResult in lateResults {
            let persistence = InMemoryMergeSessionPersistence()
            var snapshot = makeMergeSnapshot(jobID: "job_1", status: .artifactReady)
            snapshot.artifactDraft = MergeArtifactDraftSnapshot(
                baseRevision: 0,
                baseDocumentHash: "sha256:stale",
                documentJSON: original.documentJSON,
                tags: original.presentation.tags,
                rate: original.presentation.rate,
                preservationManifest: Data("manifest-original".utf8),
                pendingSave: MergePendingArtifactSave(
                    idempotencyKey: "save-stale-clean",
                    baseRevision: 0,
                    baseDocumentHash: "sha256:stale",
                    documentJSON: original.documentJSON,
                    tags: original.presentation.tags
                )
            )
            persistence.seed(snapshot)
            let service = ControlledDraftMergeService(initialArtifact: original)
            let staleSave = ControlledDraftSaveResponse(
                result: .failure(.conflict(code: "stale_base"))
            )
            await service.enqueueSave(staleSave)
            let store = makeStore(
                service: service,
                persistence: persistence,
                keys: MergeKeySequence(["must-not-be-used"])
            )
            store.start()
            await waitForMergeStore { store.phase == .ready }
            await waitForControlledDraftSave(staleSave)
            let lateFetch = ControlledDraftArtifactResponse(result: lateResult)
            await service.enqueueArtifact(lateFetch)
            await staleSave.resume()
            await waitForControlledDraftArtifact(lateFetch)

            store.invalidateLifetime()
            let stateBeforeLateResult = store.artifactDraftSyncState
            let snapshotBeforeLateResult = persistence.snapshot(actorID: "actor_1")
            let saveCountBeforeLateResult = persistence.saves.count
            await lateFetch.resume()
            for _ in 0..<100 { await Task.yield() }

            XCTAssertEqual(store.artifactDraftSyncState, stateBeforeLateResult)
            XCTAssertEqual(
                persistence.snapshot(actorID: "actor_1"),
                snapshotBeforeLateResult
            )
            XCTAssertEqual(persistence.saves.count, saveCountBeforeLateResult)
        }
    }

    func testBackKeepsReadyPhaseAndPersistsDraftWhileDebounceContinues() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let sleeper = ControlledMergeSleeper()
        let store = await readyStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            keys: MergeKeySequence(["save-background"])
        )
        await service.enqueueSave(.success(saveResult(revision: 2)))
        let edited = document(id: "blk_background", text: "Background")

        store.updateArtifactDraft(
            documentJSON: edited,
            preservationManifest: Data("manifest-background".utf8)
        )
        store.suspend(reason: nil)

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(
            persistence.snapshot(actorID: "actor_1")?.artifactDraft?.documentJSON,
            edited
        )
        await waitForPendingDraftSleep(sleeper)
        let sleepCalls = await sleeper.calls
        XCTAssertEqual(sleepCalls, [600_000_000])
        await sleeper.resumeNext()
        await waitForMergeStore { store.artifactDraftSyncState == .clean }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.artifact?.latestRevision, 2)
        let saveCalls = await service.saveCalls
        XCTAssertEqual(saveCalls.map(\.request.idempotencyKey), ["save-background"])
    }

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
        persistence: InMemoryMergeSessionPersistence,
        sleeper: any MergeSleeping = ImmediateMergeSleeper(),
        keys: MergeKeySequence = MergeKeySequence(["unused"])
    ) async -> MergeSessionStore {
        persistence.seed(makeMergeSnapshot(jobID: "job_1", status: .artifactReady))
        await service.enqueueJob(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            keys: keys
        )
        store.start()
        await waitForMergeStore { store.phase == .ready }
        return store
    }

    private func makeStore(
        service: any CoreMergeServing,
        persistence: InMemoryMergeSessionPersistence,
        sleeper: any MergeSleeping = ImmediateMergeSleeper(),
        keys: MergeKeySequence = MergeKeySequence(["unused"])
    ) -> MergeSessionStore {
        MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            idempotencyKey: { keys.next() },
            pollDelaysNanoseconds: [0],
            maxPollAttempts: 3
        )
    }

    private func document(id: String, text: String) -> Data {
        Data(
            #"{"blocks":[{"content":[{"text":"\#(text)","type":"text"}],"id":"\#(id)","type":"paragraph"}],"meta":{},"schemaVersion":"card_doc.v1"}"#.utf8
        )
    }

    private func draftArtifact(
        revision: Int,
        documentJSON: Data? = nil,
        tags: [String] = [],
        rate: Int = 1
    ) -> MergeArtifact {
        let base = makeMergeArtifact()
        return MergeArtifact(
            artifactID: base.artifactID,
            jobID: base.jobID,
            capabilityID: base.capabilityID,
            outputKind: base.outputKind,
            document: base.document,
            fragments: base.fragments,
            metadata: base.metadata,
            latestRevision: revision,
            latestHash: "sha256:document-\(revision)",
            documentJSON: documentJSON ?? base.documentJSON,
            presentationHash: "sha256:presentation-\(revision)",
            presentation: MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: tags,
                rate: rate
            )
        )
    }

    private func saveResult(
        revision: Int,
        tags: [String] = [],
        rate: Int = 1
    ) -> MergeArtifactSaveResult {
        MergeArtifactSaveResult(
            artifactID: "artifact_1",
            revision: revision,
            documentHash: "sha256:document-\(revision)",
            presentationHash: "sha256:presentation-\(revision)",
            presentation: MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: tags,
                rate: rate
            )
        )
    }
}

private final class MergeKeySequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        precondition(!values.isEmpty, "A Merge idempotency key must be provided")
        return values.removeFirst()
    }
}

actor ControlledDraftSaveResponse {
    private let result: Result<MergeArtifactSaveResult, CoreMergeError>
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    init(result: Result<MergeArtifactSaveResult, CoreMergeError>) {
        self.result = result
    }

    func resolve() async throws -> MergeArtifactSaveResult {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

actor ControlledDraftArtifactResponse {
    private let result: Result<MergeArtifact, CoreMergeError>
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    init(artifact: MergeArtifact) {
        result = .success(artifact)
    }

    init(result: Result<MergeArtifact, CoreMergeError>) {
        self.result = result
    }

    func resolve() async throws -> MergeArtifact {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

actor ControlledDraftMergeService: CoreMergeServing {
    private let initialArtifact: MergeArtifact
    private var artifactResponses: [ControlledDraftArtifactResponse] = []
    private var saveResponses: [ControlledDraftSaveResponse] = []
    private(set) var saveCalls: [(jobID: String, request: MergeArtifactSaveRequest)] = []
    private(set) var commitCalls: [(jobID: String, request: MergeCommitRequest)] = []

    init(initialArtifact: MergeArtifact) {
        self.initialArtifact = initialArtifact
    }

    func enqueueSave(_ response: ControlledDraftSaveResponse) {
        saveResponses.append(response)
    }

    func enqueueArtifact(_ response: ControlledDraftArtifactResponse) {
        artifactResponses.append(response)
    }

    func capabilities() async throws -> [MergeCapability] { [] }
    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        makeMergeJob(status: .artifactReady, artifactID: initialArtifact.artifactID)
    }
    func job(id: String) async throws -> MergeJob {
        makeMergeJob(id: id, status: .artifactReady, artifactID: initialArtifact.artifactID)
    }
    func artifact(jobID: String) async throws -> MergeArtifact {
        guard !artifactResponses.isEmpty else { return initialArtifact }
        return try await artifactResponses.removeFirst().resolve()
    }
    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult {
        saveCalls.append((jobID, request))
        precondition(!saveResponses.isEmpty, "A controlled save response must be provided")
        return try await saveResponses.removeFirst().resolve()
    }
    func cancel(jobID: String) async throws -> MergeJob {
        makeMergeJob(id: jobID, status: .cancelled)
    }
    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult {
        commitCalls.append((jobID, request))
        return makeMergeCommitResult()
    }
}

func waitForControlledDraftSave(
    _ response: ControlledDraftSaveResponse,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await response.isWaiting { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for controlled Merge artifact save")
}

func waitForControlledDraftArtifact(
    _ response: ControlledDraftArtifactResponse,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await response.isWaiting { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for controlled Merge artifact fetch")
}

private func waitForPendingDraftSleep(
    _ sleeper: ControlledMergeSleeper,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await sleeper.pendingCount > 0 { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for Merge artifact debounce")
}
