import XCTest
@testable import CoreFlow

@MainActor
final class MergeTaskCoordinatorTests: XCTestCase {

    func testEditorRetirementHidesOldUIAndPersistsBeforeLatestActorActivation() async {
        let fixture = makeCoordinatorFixture(keys: ["create", "save"])
        fixture.coordinator.activate(actorID: "actor_1")
        let draft = await acceptDraft(coordinator: fixture.coordinator, service: fixture.service,
            anchorID: "a", companionID: "b", jobID: "job_1", status: .artifactReady)
        await waitForMergeCoordinator { draft.store.phase == .ready }
        fixture.coordinator.present(jobID: "job_1")
        var gate: CheckedContinuation<Void, Never>?
        var closeCount = 0
        var drainCount = 0
        let finalDocument = Data(#"{"schemaVersion":"card_doc.v1","meta":{},"blocks":[]}"#.utf8)
        fixture.coordinator.registerEditorDrain(id: UUID(), jobID: "job_1", beginClosing: {
            closeCount += 1
        }, drain: {
            drainCount += 1
            await withCheckedContinuation { gate = $0 }
            draft.store.updateArtifactDraft(documentJSON: finalDocument, preservationManifest: Data())
            return true
        })
        fixture.coordinator.deactivate()
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(fixture.coordinator.transitionState, .draining)
        XCTAssertTrue(fixture.coordinator.summaries.isEmpty)
        XCTAssertNil(fixture.coordinator.presentation)
        fixture.coordinator.activate(actorID: "actor_2")
        fixture.coordinator.activate(actorID: "actor_3")
        XCTAssertFalse(fixture.coordinator.isReady(for: "actor_3"))
        await waitForMergeCoordinator { gate != nil }
        gate?.resume()
        await waitForMergeCoordinator { fixture.coordinator.isReady(for: "actor_3") }
        XCTAssertEqual(drainCount, 1)
        XCTAssertEqual(fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]?
            .snapshot.artifactDraft?.documentJSON, finalDocument)
        XCTAssertTrue(fixture.persistence.collection(actorID: "actor_2").tasks.isEmpty)
        // The old store is invalidated only after its accepted body has been persisted.
        draft.store.updateArtifactTags(["too late"])
        XCTAssertNotEqual(draft.store.artifactDraft?.tags, ["too late"])
    }

    func testFailedEditorDrainRetainsOwnerAndRetriesLatestTarget() async {
        let fixture = makeCoordinatorFixture(keys: [])
        fixture.coordinator.activate(actorID: "actor_1")
        var attempts = 0
        var closes = 0
        fixture.coordinator.registerEditorDrain(id: UUID(), jobID: "fixture", beginClosing: {
            closes += 1
        }, drain: {
            attempts += 1
            return attempts > 1
        })
        fixture.coordinator.activate(actorID: "actor_2")
        await waitForMergeCoordinator { fixture.coordinator.transitionState == .failed }
        fixture.coordinator.activate(actorID: "actor_3")
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(fixture.coordinator.isReady(for: "actor_3"))
        fixture.coordinator.retryEditorDrain()
        await waitForMergeCoordinator { fixture.coordinator.isReady(for: "actor_3") }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(closes, 1)
    }

    func testInactiveFlushDoesNotSealEditorAndCanFlushAgain() async {
        let fixture = makeCoordinatorFixture(keys: [])
        fixture.coordinator.activate(actorID: "actor_1")
        var flushes = 0
        var closes = 0
        fixture.coordinator.registerEditorDrain(id: UUID(), jobID: "fixture", beginClosing: {
            closes += 1
        }, drain: { flushes += 1; return true })
        fixture.coordinator.setApplicationActive(false)
        await waitForMergeCoordinator { flushes == 1 }
        fixture.coordinator.setApplicationActive(true)
        fixture.coordinator.setApplicationActive(false)
        await waitForMergeCoordinator { flushes == 2 }
        XCTAssertEqual(closes, 0)
        XCTAssertTrue(fixture.coordinator.isReady(for: "actor_1"))
    }
    func testRootLifecycleDirectActivationRestoresWithoutTabBarAndDeactivatesOnLogout() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .created, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .generating))
        )

        XCTAssertTrue(
            fixture.coordinator.synchronizeLifecycle(
                verifiedActorID: "actor_1",
                isApplicationActive: true,
                isNetworkAvailable: true
            )
        )
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .working
        }
        fixture.coordinator.present(jobID: "job_1")
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_1")
        )

        XCTAssertTrue(
            fixture.coordinator.synchronizeLifecycle(
                verifiedActorID: nil,
                isApplicationActive: true,
                isNetworkAvailable: true
            )
        )
        XCTAssertTrue(fixture.coordinator.summaries.isEmpty)
        XCTAssertNil(fixture.coordinator.presentation)
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testRootLifecycleActorSwitchIgnoresOldGenerationAndRestoresNewActor() async {
        let actorOne = restoredCollection([("job_old", .created, 100)])
        var actorTwo = MergeTaskCollection.empty(actorID: "actor_2")
        actorTwo.tasks["job_new"] = makeMergeTaskRecord(
            jobID: "job_new",
            status: .created,
            createdAt: 200
        )
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeTaskCollectionStore(collection: actorOne)
        persistence.save(actorTwo)
        let coordinator = MergeTaskCoordinator(
            service: service,
            persistence: persistence,
            sleeper: ControlledMergeSleeper()
        )
        let oldResponse = await service.enqueueControlledJob(
            id: "job_old",
            .success(makeMergeJob(id: "job_old", status: .generating))
        )
        await service.enqueueJob(
            id: "job_new",
            .success(makeMergeJob(id: "job_new", status: .generating))
        )

        _ = coordinator.synchronizeLifecycle(
            verifiedActorID: "actor_1",
            isApplicationActive: true,
            isNetworkAvailable: true
        )
        await waitForControlledJob(oldResponse)
        XCTAssertTrue(
            coordinator.synchronizeLifecycle(
                verifiedActorID: "actor_2",
                isApplicationActive: true,
                isNetworkAvailable: true
            )
        )
        await oldResponse.resume()
        await waitForMergeCoordinator {
            coordinator.summary(jobID: "job_new")?.visualState == .working
        }

        XCTAssertNil(coordinator.summary(jobID: "job_old"))
        XCTAssertEqual(coordinator.summaries.map(\.jobID), ["job_new"])
        XCTAssertNotNil(
            persistence.collection(actorID: "actor_1").tasks["job_old"]
        )
    }

    func testAdoptingWorkingDraftPublishesSummaryImmediately() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1"])
        fixture.coordinator.activate(actorID: "actor_1")

        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .generating
        )

        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_1")?.visualState,
            .working
        )
        XCTAssertEqual(fixture.coordinator.summaries.map(\.jobID), ["job_1"])
    }

    func testTwoAdoptedJobsPublishIndependentNewestFirstSummaries() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1", "create-2"])
        fixture.coordinator.activate(actorID: "actor_1")

        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .generating
        )
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_2",
            companionID: "ast_2_companion",
            jobID: "job_2",
            status: .artifactReady
        )
        await waitForMergeCoordinator {
            fixture.coordinator.summaries.map(\.visualState)
                == [.complete, .working]
        }

        XCTAssertEqual(fixture.coordinator.summaries.map(\.jobID), ["job_2", "job_1"])
        XCTAssertEqual(
            fixture.coordinator.summaries.map(\.visualState),
            [.complete, .working]
        )
        XCTAssertEqual(
            Set(fixture.persistence.collection(actorID: "actor_1").tasks.keys),
            Set(["job_1", "job_2"])
        )
    }

    func testCommitCompletionHidesOnlyTargetAndPublishesCardIntent() async {
        let fixture = makeCoordinatorFixture(
            keys: ["create-1", "create-2", "commit-1"]
        )
        fixture.coordinator.activate(actorID: "actor_1")
        let first = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .artifactReady
        )
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_2",
            companionID: "ast_2_companion",
            jobID: "job_2",
            status: .generating
        )
        await fixture.service.enqueueCommit(
            jobID: "job_1",
            .success(makeMergeCommitResult(assetID: "ast_committed"))
        )

        first.store.commit()
        await waitForMergeCoordinator {
            fixture.coordinator.committedCardIntent?.jobID == "job_1"
        }

        XCTAssertEqual(fixture.coordinator.summaries.map(\.jobID), ["job_2"])
        XCTAssertEqual(
            fixture.coordinator.committedCardIntent,
            MergeCommittedCardIntent(jobID: "job_1", assetID: "ast_committed")
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )

        fixture.coordinator.acknowledgeCommittedCardIntent(jobID: "job_1")

        XCTAssertNil(fixture.coordinator.committedCardIntent)
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testVisibleProgressBecomesPreviewWhenThatJobCompletes() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1"])
        fixture.coordinator.activate(actorID: "actor_1")
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .generating
        )
        fixture.coordinator.present(jobID: "job_1")
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_1")
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )
        await waitForPendingSleep(fixture.sleeper)
        await fixture.sleeper.resumeNext()
        await waitForMergeCoordinator {
            fixture.coordinator.presentation == .preview(jobID: "job_1")
        }

        XCTAssertEqual(fixture.coordinator.completionEventJobID, "job_1")
    }

    func testAnotherJobCompletingDoesNotInterruptCurrentPreview() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1", "create-2"])
        fixture.coordinator.activate(actorID: "actor_1")
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .artifactReady
        )
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .complete
        }
        fixture.coordinator.present(jobID: "job_1")
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_2",
            companionID: "ast_2_companion",
            jobID: "job_2",
            status: .generating
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(
                makeMergeJob(
                    id: "job_2",
                    status: .artifactReady,
                    artifactID: "artifact_2"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_2",
            .success(makeMergeArtifact(jobID: "job_2", artifactID: "artifact_2"))
        )
        await waitForPendingSleep(fixture.sleeper)
        await fixture.sleeper.resumeNext()
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_2")?.visualState == .complete
        }

        XCTAssertEqual(
            fixture.coordinator.presentation,
            .preview(jobID: "job_1")
        )
    }

    func testRetryKeepsOneRecoveringSummaryAndRekeysPresentation() async {
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        collection.tasks["job_old"] = makeMergeTaskRecord(
            jobID: "job_old",
            status: .failed,
            operationID: "op_1"
        )
        let fixture = makeCoordinatorFixture(
            keys: ["create-retry"],
            collection: collection
        )
        await fixture.service.enqueueJob(
            id: "job_old",
            .success(makeMergeJob(id: "job_old", status: .failed))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_old")?.visualState == .failed
        }
        fixture.coordinator.present(jobID: "job_old")
        await fixture.service.enqueueCreate(.failure(.offline))

        fixture.coordinator.retryFailed(jobID: "job_old")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_old")?.visualState == .recovering
        }

        XCTAssertEqual(fixture.coordinator.summaries.count, 1)
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_old")
        )

        await fixture.service.enqueueCreate(
            .success(makeMergeJob(id: "job_new", status: .generating))
        )
        fixture.coordinator.setNetworkAvailable(false)
        fixture.coordinator.setNetworkAvailable(true)
        await waitForMergeCoordinator {
            fixture.coordinator.summaries.map(\.jobID) == ["job_new"]
        }

        XCTAssertEqual(fixture.coordinator.summaries.count, 1)
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_new")
        )
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_old"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_new"]
        )
    }

    func testCommittedCardIntentsAreQueuedInObservedOrder() async {
        let fixture = makeCoordinatorFixture(
            keys: ["create-1", "create-2", "commit-1", "commit-2"]
        )
        fixture.coordinator.activate(actorID: "actor_1")
        let first = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .artifactReady
        )
        let second = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_2",
            companionID: "ast_2_companion",
            jobID: "job_2",
            status: .artifactReady
        )
        await waitForMergeStore { first.store.phase == .ready }
        await waitForMergeStore { second.store.phase == .ready }
        await fixture.service.enqueueCommit(
            jobID: "job_1",
            .success(makeMergeCommitResult(assetID: "ast_1_committed"))
        )
        first.store.commit()
        await waitForMergeCoordinator {
            fixture.coordinator.committedCardIntent?.jobID == "job_1"
        }
        await fixture.service.enqueueCommit(
            jobID: "job_2",
            .success(makeMergeCommitResult(assetID: "ast_2_committed"))
        )
        second.store.commit()
        await waitForMergeStore {
            second.store.phase == .completed(assetID: "ast_2_committed")
        }

        XCTAssertEqual(fixture.coordinator.committedCardIntent?.jobID, "job_1")
        fixture.coordinator.acknowledgeCommittedCardIntent(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.committedCardIntent?.jobID == "job_2"
        }

        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
    }

    func testCommittedBlockIsFailedWithoutInventingCardIntent() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1"])
        fixture.coordinator.activate(actorID: "actor_1")
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .committedBlock
        )
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }

        XCTAssertNil(fixture.coordinator.committedCardIntent)
        fixture.coordinator.removeFailed(jobID: "job_1")
        XCTAssertTrue(fixture.coordinator.summaries.isEmpty)
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testRestoredArtifactReadyDoesNotEmitDuplicateCompletionEvent() async {
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        collection.tasks["job_1"] = makeMergeTaskRecord(
            jobID: "job_1",
            status: .artifactReady
        )
        let fixture = makeCoordinatorFixture(keys: [], collection: collection)
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .complete
        }

        XCTAssertNil(fixture.coordinator.completionEventJobID)
    }

    func testDeactivateHidesTasksWithoutDeletingActorCollection() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([
                ("job_1", .created, 100),
                ("job_2", .generating, 200),
            ])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .generating))
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summaries.count == 2
        }

        fixture.coordinator.deactivate()

        XCTAssertTrue(fixture.coordinator.summaries.isEmpty)
        XCTAssertEqual(
            fixture.persistence.collection(actorID: "actor_1").tasks.count,
            2
        )

        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .generating))
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summaries.count == 2
        }
    }

    func testNotFoundFailsOnlyTheMatchingJob() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([
                ("job_1", .created, 100),
                ("job_2", .created, 200),
            ])
        )
        await fixture.service.enqueueJob(id: "job_1", .failure(.notFound))
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
                && fixture.coordinator.summary(jobID: "job_2")?.visualState == .working
        }

        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_2")?.visualState,
            .working
        )
        XCTAssertEqual(
            fixture.persistence.collection(actorID: "actor_1").tasks.count,
            2
        )

        fixture.coordinator.removeFailed(jobID: "job_1")

        XCTAssertNil(fixture.coordinator.summary(jobID: "job_1"))
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
    }

    func testNetworkRecoveryResumesSameJobWithoutNewCreate() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .created, 100)])
        )
        fixture.coordinator.setNetworkAvailable(false)
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .recovering
        }
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )

        fixture.coordinator.setNetworkAvailable(true)
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .complete
        }

        let createCalls = await fixture.service.createCalls
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testReadyDraftStaysCompleteOfflineAndRecoveryReplaysOnlyTargetSibling() async {
        let fixture = makeCoordinatorFixture(
            keys: ["save-job-1"],
            collection: restoredCollection([
                ("job_1", .artifactReady, 100),
                ("job_2", .artifactReady, 200),
            ])
        )
        for jobID in ["job_1", "job_2"] {
            await fixture.service.enqueueJob(
                id: jobID,
                .success(
                    makeMergeJob(
                        id: jobID,
                        status: .artifactReady,
                        artifactID: "artifact_\(jobID)"
                    )
                )
            )
            await fixture.service.enqueueArtifact(
                jobID: jobID,
                .success(
                    makeMergeArtifact(
                        jobID: jobID,
                        artifactID: "artifact_\(jobID)"
                    )
                )
            )
        }
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .complete
                && fixture.coordinator.summary(jobID: "job_2")?.visualState == .complete
        }
        let target = try? XCTUnwrap(fixture.coordinator.session(jobID: "job_1"))
        let sibling = try? XCTUnwrap(fixture.coordinator.session(jobID: "job_2"))

        fixture.coordinator.setNetworkAvailable(false)
        target?.updateArtifactTags([" Offline "])

        XCTAssertEqual(target?.phase, .ready)
        XCTAssertEqual(target?.artifactDraftSyncState, .unsynced(.offline))
        XCTAssertEqual(sibling?.phase, .ready)
        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_1")?.visualState,
            .complete
        )
        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_2")?.visualState,
            .complete
        )
        let persistedPending = fixture.persistence.collection(actorID: "actor_1")
            .tasks["job_1"]?.snapshot.artifactDraft?.pendingSave
        XCTAssertEqual(persistedPending?.idempotencyKey, "save-job-1")
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1")
                .tasks["job_2"]?.snapshot.artifactDraft?.pendingSave
        )
        await fixture.service.enqueueSave(
            jobID: "job_1",
            .success(
                MergeArtifactSaveResult(
                    artifactID: "artifact_job_1",
                    revision: 2,
                    documentHash: "sha256:job-1-document-2",
                    presentationHash: "sha256:job-1-presentation-2",
                    presentation: MergeArtifactPresentation(
                        schemaVersion: "merge_artifact_presentation.v1",
                        tags: ["Offline"],
                        rate: 1
                    )
                )
            )
        )

        fixture.coordinator.setNetworkAvailable(true)
        await waitForMergeCoordinator {
            target?.artifactDraftSyncState == .clean
        }

        let saveCalls = await fixture.service.saveCalls
        XCTAssertEqual(saveCalls.map(\.jobID), ["job_1"])
        XCTAssertEqual(saveCalls.first?.request.idempotencyKey, "save-job-1")
        XCTAssertEqual(saveCalls.first?.request.tags, ["Offline"])
        XCTAssertEqual(sibling?.artifact?.latestRevision, 1)
    }

    func testActorChangeRejectsLateDraftSaveAcknowledgement() async {
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        collection.tasks["job_1"] = makeMergeTaskRecord(
            jobID: "job_1",
            status: .artifactReady,
            operationID: "op_1"
        )
        let persistence = InMemoryMergeTaskCollectionStore(collection: collection)
        let service = ControlledDraftMergeService(initialArtifact: makeMergeArtifact())
        let response = ControlledDraftSaveResponse(
            result: .success(
                MergeArtifactSaveResult(
                    artifactID: "artifact_1",
                    revision: 2,
                    documentHash: "sha256:late-2",
                    presentationHash: "sha256:late-presentation-2",
                    presentation: MergeArtifactPresentation(
                        schemaVersion: "merge_artifact_presentation.v1",
                        tags: ["Late"],
                        rate: 1
                    )
                )
            )
        )
        await service.enqueueSave(response)
        var keys = ["save-late"]
        let coordinator = MergeTaskCoordinator(
            service: service,
            persistence: persistence,
            sleeper: ImmediateMergeSleeper(),
            pollingGate: MergePollingGate(maxConcurrentRequests: 4),
            idempotencyKey: { keys.removeFirst() },
            operationID: { "unused" }
        )
        coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            coordinator.summary(jobID: "job_1")?.visualState == .complete
        }
        let staleStore = try? XCTUnwrap(coordinator.session(jobID: "job_1"))
        staleStore?.updateArtifactTags(["Late"])
        await waitForControlledDraftSave(response)
        let pendingBeforeActorChange = persistence.collection(actorID: "actor_1")
            .tasks["job_1"]?.snapshot.artifactDraft?.pendingSave

        coordinator.activate(actorID: "actor_2")
        await response.resume()
        for _ in 0..<20 { await Task.yield() }

        let actorOne = persistence.collection(actorID: "actor_1")
        XCTAssertEqual(
            actorOne.tasks["job_1"]?.snapshot.artifactDraft?.pendingSave,
            pendingBeforeActorChange
        )
        XCTAssertEqual(
            actorOne.tasks["job_1"]?.snapshot.artifactDraft?.baseRevision,
            1
        )
        XCTAssertEqual(staleStore?.artifact?.latestRevision, 1)
        XCTAssertEqual(
            persistence.collection(actorID: "actor_2"),
            .empty(actorID: "actor_2")
        )
        XCTAssertTrue(coordinator.summaries.isEmpty)
    }

    func testPausedServerFailureRetriesSameJobWithoutCreatingReplacement() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([
                ("job_1", .created, 100),
                ("job_2", .created, 200),
            ])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .failure(.server(code: "temporary_failure"))
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .recovering
                && fixture.coordinator.summary(jobID: "job_2")?.visualState
                    == .working
        }
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry, .cancel]
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )
        fixture.coordinator.retryFailed(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .complete
        }

        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_2")?.visualState,
            .working
        )
        let createCalls = await fixture.service.createCalls
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testFirstFetchTimeoutCancelFailureRetainsCanonicalPointerAndSibling() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([
                ("job_1", .created, 100),
                ("job_2", .created, 200),
            ])
        )
        await fixture.service.enqueueJob(id: "job_1", .failure(.timeout))
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .recovering
                && fixture.coordinator.summary(jobID: "job_2")?.visualState
                    == .working
        }
        XCTAssertNil(fixture.coordinator.session(jobID: "job_1")?.job)
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry, .cancel]
        )
        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .failure(.server(code: "cancel_failed"))
        )
        await fixture.service.enqueueJob(id: "job_1", .failure(.timeout))

        fixture.coordinator.cancelFailed(jobID: "job_1")
        await waitForMergeStore {
            fixture.coordinator.session(jobID: "job_1")?.phase
                == .paused(.timeout)
        }

        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
        let cancelCalls = await fixture.service.cancelCalls
        let createCalls = await fixture.service.createCalls
        XCTAssertEqual(cancelCalls, ["job_1"])
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testNilStatusRestoredCanonicalJobCancelsWithoutReplacementAndIsolatesSibling() async {
        var collection = restoredCollection([("job_2", .created, 200)])
        collection.tasks["job_1"] = MergeTaskRecord(
            operationID: "op_job_1",
            snapshot: makeMergeSnapshot(
                jobID: "job_1",
                status: nil,
                createKey: "create_job_1"
            ),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            replacesJobID: nil
        )
        let fixture = makeCoordinatorFixture(keys: [], collection: collection)
        await fixture.service.enqueueJob(id: "job_1", .failure(.timeout))
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .recovering
                && fixture.coordinator.summary(jobID: "job_2")?.visualState
                    == .working
        }
        let target = fixture.coordinator.session(jobID: "job_1")
        XCTAssertNil(target?.job)
        XCTAssertEqual(target?.activeSnapshot?.jobID, "job_1")
        XCTAssertNil(target?.activeSnapshot?.lastStatus)
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry, .cancel]
        )
        fixture.coordinator.present(jobID: "job_1")
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_1")
        )

        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .failure(.server(code: "cancel_failed"))
        )
        await fixture.service.enqueueJob(id: "job_1", .failure(.timeout))
        fixture.coordinator.cancelFailed(jobID: "job_1")
        await waitForMergeStore {
            fixture.coordinator.session(jobID: "job_1")?.phase
                == .paused(.timeout)
        }

        XCTAssertEqual(
            fixture.coordinator.session(jobID: "job_1")?
                .activeSnapshot?.jobID,
            "job_1"
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_1")
        )
        let cancelCallsAfterFailure = await fixture.service.cancelCalls
        let createCallsAfterFailure = await fixture.service.createCalls
        XCTAssertEqual(cancelCallsAfterFailure, ["job_1"])
        XCTAssertTrue(createCallsAfterFailure.isEmpty)

        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .success(makeMergeJob(id: "job_1", status: .cancelled))
        )
        fixture.coordinator.cancelFailed(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1") == nil
        }

        XCTAssertNil(fixture.coordinator.session(jobID: "job_1"))
        XCTAssertNil(fixture.coordinator.presentation)
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_2")?.visualState,
            .working
        )
        let cancelCalls = await fixture.service.cancelCalls
        let createCalls = await fixture.service.createCalls
        XCTAssertEqual(cancelCalls, ["job_1", "job_1"])
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testFirstFetchUnavailableCanonicalCancelCleansOnlyTarget() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([
                ("job_1", .created, 100),
                ("job_2", .created, 200),
            ])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .failure(.unavailable(code: "temporarily_unavailable"))
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .recovering
                && fixture.coordinator.summary(jobID: "job_2")?.visualState
                    == .working
        }
        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .success(makeMergeJob(id: "job_1", status: .cancelled))
        )

        fixture.coordinator.cancelFailed(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1") == nil
        }

        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
        let cancelCalls = await fixture.service.cancelCalls
        let createCalls = await fixture.service.createCalls
        XCTAssertEqual(cancelCalls, ["job_1"])
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testWorkingCancelUsesCanonicalServiceAndCleansAcceptedTask() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1", "create-2"])
        fixture.coordinator.activate(actorID: "actor_1")
        let target = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_1",
            companionID: "ast_1_companion",
            jobID: "job_1",
            status: .generating
        )
        _ = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_2",
            companionID: "ast_2_companion",
            jobID: "job_2",
            status: .generating
        )
        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .success(makeMergeJob(id: "job_1", status: .cancelled))
        )

        target.store.cancel()
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1") == nil
        }

        let cancelCalls = await fixture.service.cancelCalls
        XCTAssertEqual(cancelCalls, ["job_1"])
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_2"]
        )
    }

    func testArtifactDecodingFailureRetriesSameJobWithoutCreatingReplacement() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .artifactReady, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .failure(.decoding)
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry, .cancel]
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )

        fixture.coordinator.retryFailed(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .complete
        }

        XCTAssertEqual(fixture.coordinator.summaries.map(\.jobID), ["job_1"])
        let createCalls = await fixture.service.createCalls
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testArtifactNotFoundRetriesSameJobWithoutReplacement() async {
        let fixture = makeCoordinatorFixture(
            keys: ["must-not-create"],
            collection: restoredCollection([
                ("job_1", .artifactReady, 100),
                ("job_2", .created, 200),
            ])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .failure(.notFound)
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
                && fixture.coordinator.summary(jobID: "job_2")?.visualState
                    == .working
        }
        fixture.coordinator.present(jobID: "job_1")
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry, .cancel]
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )
        await fixture.service.enqueueCreate(
            .success(makeMergeJob(id: "job_duplicate", status: .generating))
        )

        fixture.coordinator.retryFailed(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .complete
        }

        XCTAssertEqual(
            fixture.coordinator.presentation,
            .preview(jobID: "job_1")
        )
        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_2")?.visualState,
            .working
        )
        let createCalls = await fixture.service.createCalls
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testOfflinePauseOffersRetryWithoutDestructiveRemoval() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .created, 100)])
        )
        fixture.coordinator.setNetworkAvailable(false)
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .recovering
        }

        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry]
        )
        XCTAssertFalse(
            fixture.coordinator.session(jobID: "job_1")?
                .canCancelCanonicalJob ?? true
        )
        fixture.coordinator.removeFailed(jobID: "job_1")
        XCTAssertNotNil(fixture.coordinator.summary(jobID: "job_1"))
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testTransientPauseWithCanonicalJobOffersRetryAndCancel() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .created, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForPendingSleep(fixture.sleeper)
        await fixture.service.enqueueJob(
            id: "job_1",
            .failure(.server(code: "temporary_failure"))
        )
        await fixture.sleeper.resumeNext()
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState
                == .recovering
        }

        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.retry, .cancel]
        )
        fixture.coordinator.removeFailed(jobID: "job_1")
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testCancelFailureRetainsDurableJobPointer() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .artifactReady, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .failure(.notFound)
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }
        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .failure(.server(code: "cancel_failed"))
        )
        await fixture.service.enqueueJob(id: "job_1", .failure(.offline))

        fixture.coordinator.cancelFailed(jobID: "job_1")
        await waitForMergeStore {
            fixture.coordinator.session(jobID: "job_1")?.phase
                == .paused(.offline)
        }

        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
        XCTAssertEqual(
            fixture.coordinator.session(jobID: "job_1")?.job?.jobID,
            "job_1"
        )
        let cancelCalls = await fixture.service.cancelCalls
        XCTAssertEqual(cancelCalls, ["job_1"])
    }

    func testCanonicalCancellationCleansOnlyTargetAndPreservesSibling() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([
                ("job_1", .artifactReady, 100),
                ("job_2", .created, 200),
            ])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .failure(.notFound)
        )
        await fixture.service.enqueueJob(
            id: "job_2",
            .success(makeMergeJob(id: "job_2", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
                && fixture.coordinator.summary(jobID: "job_2")?.visualState
                    == .working
        }
        await fixture.service.enqueueCancel(
            jobID: "job_1",
            .success(makeMergeJob(id: "job_1", status: .cancelled))
        )

        fixture.coordinator.cancelFailed(jobID: "job_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1") == nil
        }

        let persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNil(persisted.tasks["job_1"])
        XCTAssertNotNil(persisted.tasks["job_2"])
        XCTAssertEqual(
            fixture.coordinator.summary(jobID: "job_2")?.visualState,
            .working
        )
        let cancelCalls = await fixture.service.cancelCalls
        XCTAssertEqual(cancelCalls, ["job_1"])
    }

    func testPendingCreationRelaunchReplaysExactRequestAndPromotesOnce() async {
        let pendingSnapshot = makeMergeSnapshot(
            jobID: nil,
            createKey: "create-stable"
        )
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        collection.pendingCreations["op_pending"] = MergeTaskRecord(
            operationID: "op_pending",
            snapshot: pendingSnapshot,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            replacesJobID: nil
        )
        let fixture = makeCoordinatorFixture(keys: [], collection: collection)
        await fixture.service.enqueueCreate(
            .success(makeMergeJob(id: "job_restored", status: .generating))
        )

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_restored") != nil
        }

        let createCalls = await fixture.service.createCalls
        XCTAssertEqual(createCalls, [pendingSnapshot.createRequest])
        let restored = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertTrue(restored.pendingCreations.isEmpty)
        XCTAssertEqual(restored.tasks["job_restored"]?.operationID, "op_pending")
    }

    func testNotFoundReplacementReusesOneKeyAndRekeysPresentation() async {
        let fixture = makeCoordinatorFixture(
            keys: ["create-replacement"],
            collection: restoredCollection([("job_old", .created, 100)])
        )
        await fixture.service.enqueueJob(id: "job_old", .failure(.notFound))
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_old")?.visualState == .failed
        }
        fixture.coordinator.present(jobID: "job_old")
        await fixture.service.enqueueCreate(.failure(.offline))

        fixture.coordinator.retryFailed(jobID: "job_old")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_old")?.visualState == .recovering
        }
        await waitForMergeStore {
            fixture.coordinator.session(jobID: "job_old")?.phase
                == .paused(.offline)
        }

        var persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNotNil(persisted.tasks["job_old"])
        XCTAssertEqual(
            persisted.pendingCreations.values.first?
                .snapshot.createRequest.idempotencyKey,
            "create-replacement"
        )
        await fixture.service.enqueueCreate(
            .success(makeMergeJob(id: "job_new", status: .generating))
        )

        fixture.coordinator.retryFailed(jobID: "job_old")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_new")?.visualState == .working
        }

        let createCalls = await fixture.service.createCalls
        XCTAssertEqual(createCalls.count, 2)
        XCTAssertEqual(createCalls.first, createCalls.last)
        persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNil(persisted.tasks["job_old"])
        XCTAssertNotNil(persisted.tasks["job_new"])
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .progress(jobID: "job_new")
        )
    }

    func testRestoredCompleteDoesNotEmitCompletionHapticEvent() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .artifactReady, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(
                makeMergeJob(
                    id: "job_1",
                    status: .artifactReady,
                    artifactID: "artifact_1"
                )
            )
        )
        await fixture.service.enqueueArtifact(
            jobID: "job_1",
            .success(makeMergeArtifact(jobID: "job_1", artifactID: "artifact_1"))
        )

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .complete
        }

        XCTAssertNil(fixture.coordinator.completionEventJobID)
    }

    func testCommittedBlockStaysExplicitlyRemovableWithoutCardIntent() async {
        let fixture = makeCoordinatorFixture(
            keys: [],
            collection: restoredCollection([("job_1", .committing, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .committedBlock))
        )

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }

        XCTAssertNil(fixture.coordinator.committedCardIntent)
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_1"),
            [.remove]
        )
        fixture.coordinator.retryFailed(jobID: "job_1")
        XCTAssertEqual(
            fixture.coordinator.session(jobID: "job_1")?.phase,
            .completed(assetID: nil)
        )
        let createCalls = await fixture.service.createCalls
        XCTAssertTrue(createCalls.isEmpty)
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testCanonicalFailedTaskDoesNotReplaceOnApplicationRecoveryUntilExplicitRetry() async {
        let fixture = makeCoordinatorFixture(
            keys: ["replacement-key"],
            collection: restoredCollection([("job_1", .failed, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .failed))
        )
        let replacement = await fixture.service.enqueueControlledCreate(
            idempotencyKey: "replacement-key",
            .success(makeMergeJob(id: "job_2", status: .failed))
        )

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }
        fixture.coordinator.present(jobID: "job_1")
        let original = fixture.persistence.collection(actorID: "actor_1")
            .tasks["job_1"]

        fixture.coordinator.setApplicationActive(false)
        fixture.coordinator.setApplicationActive(true)
        let didStartAutomatically = fixture.coordinator
            .session(jobID: "job_1")?.isOperationInFlight == true

        let automaticCreateCalls = await fixture.service.createCalls
        XCTAssertFalse(didStartAutomatically)
        XCTAssertTrue(automaticCreateCalls.isEmpty)
        var persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertEqual(Set(persisted.tasks.keys), ["job_1"])
        XCTAssertTrue(persisted.pendingCreations.isEmpty)
        XCTAssertEqual(persisted.tasks["job_1"], original)
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .failure(jobID: "job_1")
        )

        if didStartAutomatically {
            await waitForControlledCreate(replacement)
            await replacement.resume()
            return
        }

        fixture.coordinator.retryFailed(jobID: "job_1")
        await waitForControlledCreate(replacement)
        await replacement.resume()
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_2")?.visualState == .failed
        }

        let createCalls = await fixture.service.createCalls
        XCTAssertEqual(createCalls.map(\.idempotencyKey), ["replacement-key"])
        persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNil(persisted.tasks["job_1"])
        XCTAssertNotNil(persisted.tasks["job_2"])
        XCTAssertTrue(persisted.pendingCreations.isEmpty)
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .failure(jobID: "job_2")
        )
    }

    func testCanonicalFailedTaskDoesNotReplaceOnNetworkRecovery() async {
        let fixture = makeCoordinatorFixture(
            keys: ["replacement-key"],
            collection: restoredCollection([("job_1", .failed, 100)])
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .failed))
        )
        let replacement = await fixture.service.enqueueControlledCreate(
            idempotencyKey: "replacement-key",
            .success(makeMergeJob(id: "job_2", status: .failed))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }
        fixture.coordinator.present(jobID: "job_1")
        let original = fixture.persistence.collection(actorID: "actor_1")
            .tasks["job_1"]

        fixture.coordinator.setNetworkAvailable(false)
        fixture.coordinator.setNetworkAvailable(true)
        let didStartAutomatically = fixture.coordinator
            .session(jobID: "job_1")?.isOperationInFlight == true

        let automaticCreateCalls = await fixture.service.createCalls
        XCTAssertFalse(didStartAutomatically)
        XCTAssertTrue(automaticCreateCalls.isEmpty)
        let persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertEqual(Set(persisted.tasks.keys), ["job_1"])
        XCTAssertTrue(persisted.pendingCreations.isEmpty)
        XCTAssertEqual(persisted.tasks["job_1"], original)
        XCTAssertEqual(
            fixture.coordinator.presentation,
            .failure(jobID: "job_1")
        )

        if didStartAutomatically {
            await waitForControlledCreate(replacement)
            await replacement.resume()
        }
    }

    func testFailedReplacementKeepsRemoveAndRemovesOnlyReplacementTarget() async {
        let fixture = makeCoordinatorFixture(
            keys: ["replacement-key"],
            collection: restoredCollection([
                ("job_old", .failed, 100),
                ("job_sibling", .generating, 200),
            ])
        )
        await fixture.service.enqueueJob(
            id: "job_old",
            .success(makeMergeJob(id: "job_old", status: .failed))
        )
        await fixture.service.enqueueJob(
            id: "job_sibling",
            .success(makeMergeJob(id: "job_sibling", status: .generating))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_old")?.visualState == .failed
                && fixture.coordinator.summary(jobID: "job_sibling")?.visualState
                    == .working
        }
        fixture.coordinator.present(jobID: "job_old")
        await fixture.service.enqueueCreate(.failure(.offline))

        fixture.coordinator.retryFailed(jobID: "job_old")
        await waitForMergeStore {
            fixture.coordinator.session(jobID: "job_old")?.phase
                == .paused(.offline)
        }

        var persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertEqual(persisted.pendingCreations.count, 1)
        XCTAssertNotNil(persisted.tasks["job_old"])
        XCTAssertNotNil(persisted.tasks["job_sibling"])
        XCTAssertEqual(
            fixture.coordinator.failureActions(jobID: "job_old"),
            [.retry, .remove]
        )

        fixture.coordinator.removeFailed(jobID: "job_old")

        persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertTrue(persisted.pendingCreations.isEmpty)
        XCTAssertNil(persisted.tasks["job_old"])
        XCTAssertNotNil(persisted.tasks["job_sibling"])
        XCTAssertNil(fixture.coordinator.summary(jobID: "job_old"))
        XCTAssertEqual(
            fixture.coordinator.presentation,
            nil
        )
        fixture.coordinator.session(jobID: "job_sibling")?.suspend(reason: nil)
        await fixture.sleeper.resumeNext()
    }

    func testSubmittedCreateDismissalSurvivesLostResponseAndRelaunch() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeTaskCollectionStore(
            collection: .empty(actorID: "actor_1")
        )
        let firstSleeper = ControlledMergeSleeper()
        let first = MergeTaskCoordinator(
            service: service,
            persistence: persistence,
            sleeper: firstSleeper,
            pollingGate: MergePollingGate(maxConcurrentRequests: 4),
            idempotencyKey: { "create-stable" },
            operationID: { "op_submitted" }
        )
        first.activate(actorID: "actor_1")
        await service.enqueueCapabilities(.success([makeMergeCapability()]))
        let lostResponse = await service.enqueueControlledCreate(
            idempotencyKey: "create-stable",
            .success(makeMergeJob(id: "job_accepted", status: .failed))
        )
        let draft = first.makeDraft(anchor: makeMergeSource("ast_anchor"))
        draft.store.start()
        await waitForMergeStore { draft.store.phase == .selection }
        draft.store.toggleSelection(makeMergeSource("ast_companion"))
        draft.store.create()
        await waitForControlledCreate(lostResponse)

        first.abandon(draft)

        var collection = persistence.collection(actorID: "actor_1")
        XCTAssertEqual(
            collection.pendingCreations["op_submitted"]?
                .snapshot.createRequest.idempotencyKey,
            "create-stable"
        )
        XCTAssertTrue(collection.tasks.isEmpty)
        first.deactivate()

        let relaunched = MergeTaskCoordinator(
            service: service,
            persistence: persistence,
            sleeper: ControlledMergeSleeper(),
            pollingGate: MergePollingGate(maxConcurrentRequests: 4),
            idempotencyKey: {
                XCTFail("A restored pending create must reuse its persisted key")
                return "unexpected-key"
            },
            operationID: { "op_relaunch" }
        )
        relaunched.activate(actorID: "actor_2")
        await lostResponse.resume()
        await waitForMergeStore { draft.store.createResponseCount == 1 }

        XCTAssertTrue(relaunched.summaries.isEmpty)
        collection = persistence.collection(actorID: "actor_1")
        XCTAssertNotNil(collection.pendingCreations["op_submitted"])
        XCTAssertTrue(collection.tasks.isEmpty)
        XCTAssertEqual(
            persistence.collection(actorID: "actor_2"),
            .empty(actorID: "actor_2")
        )

        let replay = await service.enqueueControlledCreate(
            idempotencyKey: "create-stable",
            .success(makeMergeJob(id: "job_accepted", status: .failed))
        )
        relaunched.activate(actorID: "actor_1")
        await waitForControlledCreate(replay)
        await replay.resume()
        await waitForMergeCoordinator {
            relaunched.summary(jobID: "job_accepted")?.visualState == .failed
        }

        let createCalls = await service.createCalls
        XCTAssertEqual(createCalls.count, 2)
        XCTAssertEqual(createCalls.first, createCalls.last)
        collection = persistence.collection(actorID: "actor_1")
        XCTAssertTrue(collection.pendingCreations.isEmpty)
        XCTAssertEqual(Set(collection.tasks.keys), ["job_accepted"])
        XCTAssertEqual(
            collection.tasks["job_accepted"]?.operationID,
            "op_submitted"
        )
    }

    func testSameActorReactivationInvalidatesStaleDraftOwnership() async {
        let fixture = makeCoordinatorFixture(keys: ["create-1"])
        fixture.coordinator.activate(actorID: "actor_1")
        await fixture.service.enqueueCapabilities(.success([makeMergeCapability()]))
        let draft = fixture.coordinator.makeDraft(anchor: makeMergeSource("ast_1"))
        draft.store.start()
        await waitForMergeStore { draft.store.phase == .selection }
        draft.store.toggleSelection(makeMergeSource("ast_companion"))
        let staleCreate = await fixture.service.enqueueControlledCreate(
            idempotencyKey: "create-1",
            .success(makeMergeJob(id: "job_stale", status: .generating))
        )
        draft.store.create()
        await waitForControlledCreate(staleCreate)

        let restoredCreate = await fixture.service.enqueueControlledCreate(
            idempotencyKey: "create-1",
            .success(makeMergeJob(id: "job_current", status: .failed))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForControlledCreate(restoredCreate)
        await restoredCreate.resume()
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_current")?.visualState == .failed
        }

        await staleCreate.resume()
        await waitForMergeStore { draft.store.createResponseCount == 1 }

        let staleReuse = await fixture.service.enqueueControlledCreate(
            idempotencyKey: "create-1",
            .success(makeMergeJob(id: "job_reused", status: .failed))
        )
        let createCallCountBeforeReuse = await fixture.service.createCalls.count
        draft.store.resume()
        let didAttemptReuse = draft.store.isOperationInFlight
        XCTAssertFalse(didAttemptReuse)
        if didAttemptReuse {
            await waitForControlledCreate(staleReuse)
            await staleReuse.resume()
            await waitForMergeStore { draft.store.createResponseCount == 2 }
        }

        let createCallCountAfterReuse = await fixture.service.createCalls.count
        XCTAssertEqual(createCallCountAfterReuse, createCallCountBeforeReuse)
        XCTAssertNil(fixture.coordinator.adopt(draft))
        XCTAssertNil(draft.store.activeSnapshot?.jobID)
        XCTAssertEqual(
            Set(fixture.persistence.collection(actorID: "actor_1").tasks.keys),
            Set(["job_current"])
        )
        let currentSession = fixture.coordinator.session(jobID: "job_current")
        XCTAssertNotNil(currentSession)
        XCTAssertFalse(currentSession === draft.store)

        draft.store.suspend(reason: nil)
        await fixture.sleeper.resumeNext()
    }

    func testSameActorReactivationInvalidatesRetainedAcceptedRuntime() async {
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        collection.tasks["job_1"] = makeMergeTaskRecord(
            jobID: "job_1",
            status: .failed,
            operationID: "op_1"
        )
        let fixture = makeCoordinatorFixture(
            keys: ["stale-retry"],
            collection: collection
        )
        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .failed))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }
        let retainedStore = fixture.coordinator.session(jobID: "job_1")!

        await fixture.service.enqueueJob(
            id: "job_1",
            .success(makeMergeJob(id: "job_1", status: .failed))
        )
        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }
        let staleReuse = await fixture.service.enqueueControlledCreate(
            idempotencyKey: "stale-retry",
            .success(makeMergeJob(id: "job_reused", status: .failed))
        )
        let createCallCountBeforeReuse = await fixture.service.createCalls.count

        retainedStore.retryGeneration()
        let didAttemptReuse = retainedStore.isOperationInFlight
        XCTAssertFalse(didAttemptReuse)
        if didAttemptReuse {
            await waitForControlledCreate(staleReuse)
            await staleReuse.resume()
            await waitForMergeStore { retainedStore.createResponseCount == 1 }
        }

        let createCallCountAfterReuse = await fixture.service.createCalls.count
        XCTAssertEqual(createCallCountAfterReuse, createCallCountBeforeReuse)
        let persisted = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertEqual(Set(persisted.tasks.keys), Set(["job_1"]))
        XCTAssertTrue(persisted.pendingCreations.isEmpty)
        XCTAssertFalse(
            fixture.coordinator.session(jobID: "job_1") === retainedStore
        )
    }

    func testEmptyCommittedAssetIDIsVisibleFailedAndRemovable() async {
        var snapshot = makeMergeSnapshot(
            jobID: "job_1",
            status: .committedCard
        )
        snapshot.committedAssetID = ""
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        collection.tasks["job_1"] = MergeTaskRecord(
            operationID: "op_1",
            snapshot: snapshot,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            replacesJobID: nil
        )
        let fixture = makeCoordinatorFixture(keys: [], collection: collection)

        fixture.coordinator.activate(actorID: "actor_1")
        await waitForMergeCoordinator {
            fixture.coordinator.summary(jobID: "job_1")?.visualState == .failed
        }

        XCTAssertNil(fixture.coordinator.committedCardIntent)
        fixture.coordinator.removeFailed(jobID: "job_1")
        XCTAssertTrue(fixture.coordinator.summaries.isEmpty)
        XCTAssertNil(
            fixture.persistence.collection(actorID: "actor_1").tasks["job_1"]
        )
    }

    func testAbandonRevokesOnlyExactCurrentUnadoptedDraft() async {
        let fixture = makeCoordinatorFixture(keys: ["create-adopted"])
        fixture.coordinator.activate(actorID: "actor_1")

        let pending = fixture.coordinator.makeDraft(
            anchor: makeMergeSource("ast_pending")
        )
        pending.persistence.save(
            makeMergeSnapshot(jobID: nil, createKey: "pending-key")
        )
        let canonical = fixture.coordinator.makeDraft(
            anchor: makeMergeSource("ast_canonical")
        )
        canonical.persistence.save(
            makeMergeSnapshot(
                jobID: "job_canonical",
                status: .generating,
                createKey: "canonical-key"
            )
        )
        let sibling = fixture.coordinator.makeDraft(
            anchor: makeMergeSource("ast_sibling")
        )
        sibling.persistence.save(
            makeMergeSnapshot(
                jobID: "job_sibling",
                status: .generating,
                createKey: "sibling-key"
            )
        )
        let adopted = await acceptDraft(
            coordinator: fixture.coordinator,
            service: fixture.service,
            anchorID: "ast_adopted",
            companionID: "ast_adopted_companion",
            jobID: "job_adopted",
            status: .generating
        )

        fixture.coordinator.abandon(pending)
        var collection = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNil(collection.pendingCreations[pending.operationID])
        XCTAssertNotNil(collection.tasks["job_canonical"])
        XCTAssertNotNil(collection.tasks["job_sibling"])
        XCTAssertNotNil(collection.tasks["job_adopted"])

        fixture.coordinator.abandon(canonical)
        collection = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNil(collection.tasks["job_canonical"])
        XCTAssertNotNil(collection.tasks["job_sibling"])
        XCTAssertNotNil(collection.tasks["job_adopted"])

        let capabilityCallsBeforeReuse =
            await fixture.service.capabilityCallCount
        pending.store.start()
        canonical.store.start()
        await Task.yield()
        let capabilityCallsAfterReuse =
            await fixture.service.capabilityCallCount
        XCTAssertEqual(
            capabilityCallsAfterReuse,
            capabilityCallsBeforeReuse
        )
        XCTAssertEqual(pending.store.phase, .idle)
        XCTAssertEqual(canonical.store.phase, .idle)

        fixture.coordinator.abandon(adopted)
        XCTAssertTrue(
            fixture.coordinator.session(jobID: "job_adopted")
                === adopted.store
        )
        XCTAssertNotNil(
            fixture.persistence.collection(actorID: "actor_1")
                .tasks["job_adopted"]
        )

        let stale = fixture.coordinator.makeDraft(
            anchor: makeMergeSource("ast_stale")
        )
        stale.persistence.save(
            makeMergeSnapshot(jobID: nil, createKey: "stale-key")
        )
        fixture.coordinator.activate(actorID: "actor_2")
        fixture.coordinator.abandon(stale)

        collection = fixture.persistence.collection(actorID: "actor_1")
        XCTAssertNotNil(collection.pendingCreations[stale.operationID])
        XCTAssertNotNil(collection.tasks["job_sibling"])
        XCTAssertNotNil(collection.tasks["job_adopted"])
    }
}

private func restoredCollection(
    _ jobs: [(id: String, status: MergeJobStatus, createdAt: TimeInterval)]
) -> MergeTaskCollection {
    var value = MergeTaskCollection.empty(actorID: "actor_1")
    for job in jobs {
        value.tasks[job.id] = makeMergeTaskRecord(
            jobID: job.id,
            status: job.status,
            createdAt: job.createdAt
        )
    }
    return value
}

@MainActor
private func makeCoordinatorFixture(
    keys: [String],
    collection: MergeTaskCollection = .empty(actorID: "actor_1")
) -> (
    coordinator: MergeTaskCoordinator,
    service: MockCoreMergeService,
    persistence: InMemoryMergeTaskCollectionStore,
    sleeper: ControlledMergeSleeper
) {
    let service = MockCoreMergeService()
    let persistence = InMemoryMergeTaskCollectionStore(collection: collection)
    let sleeper = ControlledMergeSleeper()
    var remainingKeys = keys
    var operationIndex = 0
    var clock: TimeInterval = 100
    let coordinator = MergeTaskCoordinator(
        service: service,
        persistence: persistence,
        sleeper: sleeper,
        pollingGate: MergePollingGate(maxConcurrentRequests: 4),
        idempotencyKey: { remainingKeys.removeFirst() },
        operationID: {
            operationIndex += 1
            return "op_\(operationIndex)"
        },
        now: {
            defer { clock += 1 }
            return Date(timeIntervalSince1970: clock)
        }
    )
    return (coordinator, service, persistence, sleeper)
}

@MainActor
@discardableResult
private func acceptDraft(
    coordinator: MergeTaskCoordinator,
    service: MockCoreMergeService,
    anchorID: String,
    companionID: String,
    jobID: String,
    status: MergeJobStatus
) async -> MergeDraftSession {
    await service.enqueueCapabilities(.success([makeMergeCapability()]))
    if status == .artifactReady {
        await service.enqueueArtifact(
            jobID: jobID,
            .success(makeMergeArtifact(jobID: jobID, artifactID: "artifact_\(jobID)"))
        )
    }
    await service.enqueueCreate(
        .success(
            makeMergeJob(
                id: jobID,
                status: status,
                artifactID: status == .artifactReady ? "artifact_\(jobID)" : nil
            )
        )
    )
    let draft = coordinator.makeDraft(anchor: makeMergeSource(anchorID))
    draft.store.start()
    await waitForMergeStore { draft.store.phase == .selection }
    draft.store.toggleSelection(makeMergeSource(companionID))
    draft.store.create()
    await waitForMergeStore { draft.store.job?.jobID == jobID }
    XCTAssertEqual(coordinator.adopt(draft), jobID)
    return draft
}

@MainActor
private func waitForMergeCoordinator(
    timeoutIterations: Int = 500,
    _ predicate: @escaping () -> Bool
) async {
    for _ in 0..<timeoutIterations {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for Merge coordinator state")
}

private func waitForPendingSleep(
    _ sleeper: ControlledMergeSleeper,
    timeout: TimeInterval = 3
) async {
    // A fixed number of yields can expire before the fixture actor is scheduled
    // while Xcode is compiling. Wait for the actual condition with a deadline.
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await sleeper.pendingCount > 0 { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("Timed out waiting for Merge poll sleep")
}
