import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class CardEditingStoreTests: XCTestCase {
    func testNewNoteSaveCreatesCanonicalCardOnce() async {
        let service = MockCardEditingService()
        let draft = CardEditingDraft(
            title: "New",
            content: "Body",
            tags: ["#idea", " idea "],
            isPublic: true
        )
        service.createResults = [
            .success(snapshot(id: "ast_new", title: "New", content: "Body", tags: ["idea"], isPublic: true))
        ]
        let store = makeNewStore(draft: draft, service: service)

        let didSave = await store.save()

        XCTAssertTrue(didSave)
        XCTAssertEqual(store.cardID, "ast_new")
        XCTAssertEqual(service.events, [.create(draft)])
        XCTAssertEqual(store.lastCommittedDraft, store.draft)
        XCTAssertFalse(store.isDirty)
    }

    func testExistingDirtyNoteSaveUsesUpdate() async {
        let service = MockCardEditingService()
        let initial = CardEditingDraft(
            title: "Existing",
            content: "Before",
            tags: [],
            isPublic: false
        )
        let revised = CardEditingDraft(
            title: "Existing",
            content: "After",
            tags: ["work"],
            isPublic: true
        )
        service.updateResults = [
            .success(snapshot(title: "Existing", content: "After", tags: ["work"], isPublic: true))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: initial,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(revised, bodyRevision: 1)

        let didSave = await store.save()

        XCTAssertTrue(didSave)
        XCTAssertEqual(service.events, [.update(cardID: "ast_1", draft: revised)])
        XCTAssertFalse(store.isDirty)
    }

    func testServerJSONReformatDoesNotMakeSavedEditorSnapshotDirty() async {
        let editorJSON = editorBlocksJSON
        let serverJSON = serverEnvelopeJSON
        let service = MockCardEditingService()
        service.updateResults = [
            .success(
                snapshot(
                    title: nil,
                    content: "Server fallback projects Body twice",
                    contentJSON: serverJSON,
                    tags: []
                )
            )
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: "Before",
                tags: [],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Body",
                contentJSON: editorJSON,
                revision: 1
            )
        )

        let didSave = await store.save()
        XCTAssertTrue(didSave)
        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Body",
                contentJSON: editorJSON,
                revision: 1
            )
        )

        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(store.lastCommittedDraft?.contentJSON, serverJSON)
        XCTAssertNotEqual(store.draft, store.lastCommittedDraft)
    }

    func testHydratedServerJSONReformatDoesNotMakeEditorSnapshotDirty() async {
        let editorJSON = editorBlocksJSON
        let serverJSON = serverEnvelopeJSON
        let service = MockCardEditingService()
        service.updateResults = [
            .success(
                snapshot(
                    title: nil,
                    content: "Server fallback projects Body twice",
                    contentJSON: serverJSON,
                    tags: []
                )
            )
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: "Before",
                tags: [],
                isPublic: false
            ),
            bodyRevision: 4,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.hydrate(
            draft: .init(
                title: nil,
                content: "Server fallback projects Body twice",
                contentJSON: serverJSON,
                tags: [],
                isPublic: false
            ),
            bodyRevision: 5,
            backgroundMediaRef: nil,
            links: []
        )

        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Body",
                contentJSON: editorJSON,
                revision: 6
            )
        )

        XCTAssertFalse(store.isDirty)
        XCTAssertNotEqual(store.draft, store.lastCommittedDraft)
        XCTAssertEqual(store.lastCommittedBodyRevision, 6)
        let didSave = await store.save()
        XCTAssertTrue(didSave)
        XCTAssertTrue(service.updateRequests.isEmpty)
    }

    func testChangedBootstrapRevisionDoesNotRebaseCommittedRevision() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: structuredDraft(
                content: "Server fallback projects Body twice",
                contentJSON: serverEnvelopeJSON
            ),
            bodyRevision: 5,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Changed",
                contentJSON: changedEditorBlocksJSON,
                revision: 6
            )
        )

        XCTAssertEqual(store.lastCommittedBodyRevision, 5)
        XCTAssertTrue(store.isDirty)
    }

    func testEquivalentRevisionDoesNotRebaseDuringActiveBackgroundWrite() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.replaceBackgroundGate = gate
        service.replaceBackgroundResults = [.success("med_new")]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: structuredDraft(
                content: "Server fallback projects Body twice",
                contentJSON: serverEnvelopeJSON
            ),
            bodyRevision: 5,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        XCTAssertTrue(store.stageBackground(validImage))
        let saveTask = Task { await store.save() }
        await waitForStore { service.replaceBackgroundRequests.count == 1 }

        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Body",
                contentJSON: editorBlocksJSON,
                revision: 6
            )
        )

        XCTAssertEqual(store.lastCommittedBodyRevision, 5)
        XCTAssertTrue(store.isDirty)
        await gate.open()
        let didSave = await saveTask.value
        XCTAssertFalse(didSave)
        XCTAssertEqual(store.lastCommittedBodyRevision, 5)
    }

    func testEquivalentRevisionDoesNotRebaseAfterUncertainUpdateFailure() async {
        let service = MockCardEditingService()
        service.updateResults = [
            .failure(.transport(code: "response_timeout"))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: structuredDraft(
                content: "Server fallback projects Body twice",
                contentJSON: serverEnvelopeJSON
            ),
            bodyRevision: 5,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Changed",
                contentJSON: changedEditorBlocksJSON,
                revision: 6
            )
        )
        let didSave = await store.save()
        XCTAssertFalse(didSave)
        XCTAssertEqual(store.failureStage, .updatingCard)

        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Body",
                contentJSON: editorBlocksJSON,
                revision: 7
            )
        )

        XCTAssertEqual(store.lastCommittedBodyRevision, 5)
        XCTAssertTrue(store.isDirty)
        XCTAssertEqual(store.failureStage, .updatingCard)
    }

    func testCommitEquivalentMatchesEditorArrayToServerEnvelope() {
        let editor = CardEditingDraft(
            title: nil,
            content: "Body",
            contentJSON: editorBlocksJSON,
            tags: [],
            isPublic: false
        )
        let server = CardEditingDraft(
            title: nil,
            content: "Server fallback projects Body twice",
            contentJSON: serverEnvelopeJSON,
            tags: [],
            isPublic: false
        )

        XCTAssertNotEqual(editor, server)
        XCTAssertTrue(editor.isCommitEquivalent(to: server))
    }

    func testCommitEquivalentRejectsBlockOrderContentAndScalarTypeChanges() {
        let original = structuredDraft(contentJSON: twoEditorBlocksJSON)
        let reversed = structuredDraft(contentJSON: reversedEditorBlocksJSON)
        let changedText = structuredDraft(contentJSON: changedEditorBlocksJSON)
        let boolean = structuredDraft(
            contentJSON: #"[{"id":"task","type":"checkListItem","props":{"checked":true},"content":[],"children":[]}]"#
        )
        let number = structuredDraft(
            contentJSON: #"[{"id":"task","type":"checkListItem","props":{"checked":1},"content":[],"children":[]}]"#
        )

        XCTAssertFalse(original.isCommitEquivalent(to: reversed))
        XCTAssertFalse(original.isCommitEquivalent(to: changedText))
        XCTAssertFalse(boolean.isCommitEquivalent(to: number))
    }

    func testCommitEquivalentRejectsNilEmptyAndDifferentMalformedJSON() {
        let legacy = structuredDraft(contentJSON: nil)
        let emptyBlocks = structuredDraft(contentJSON: "[]")
        let malformedFirst = structuredDraft(contentJSON: #"{"blocks":[}"#)
        let malformedSecond = structuredDraft(contentJSON: #"{"blocks":]}"#)

        XCTAssertFalse(legacy.isCommitEquivalent(to: emptyBlocks))
        XCTAssertFalse(
            malformedFirst.isCommitEquivalent(to: malformedSecond)
        )
        XCTAssertNotEqual(malformedFirst, malformedSecond)
    }

    func testCommitEquivalentHandlesLegacyAndBlocklessObjectBodies() {
        let legacy = structuredDraft(content: "Legacy", contentJSON: nil)
        let sameLegacy = structuredDraft(content: "Legacy", contentJSON: nil)
        let changedLegacy = structuredDraft(content: "Changed", contentJSON: nil)
        let object = structuredDraft(
            content: "Fallback",
            contentJSON: #"{"schema_version":1,"payload":{"enabled":true}}"#
        )
        let reorderedObject = structuredDraft(
            content: "Fallback",
            contentJSON: #"{"payload":{"enabled":true},"schema_version":1}"#
        )
        let changedFallback = structuredDraft(
            content: "Changed",
            contentJSON: #"{"payload":{"enabled":true},"schema_version":1}"#
        )
        let changedMetadata = CardEditingDraft(
            title: nil,
            content: "Fallback",
            contentJSON: #"{"payload":{"enabled":true},"schema_version":1}"#,
            tags: ["different"],
            isPublic: false
        )

        XCTAssertTrue(legacy.isCommitEquivalent(to: sameLegacy))
        XCTAssertFalse(legacy.isCommitEquivalent(to: changedLegacy))
        XCTAssertTrue(object.isCommitEquivalent(to: reorderedObject))
        XCTAssertFalse(object.isCommitEquivalent(to: changedFallback))
        XCTAssertFalse(object.isCommitEquivalent(to: changedMetadata))
    }

    func testCreateRetryReusesExactRawJSONForCommitEquivalentDraft() async {
        let frozen = structuredDraft(contentJSON: editorBlocksJSON)
        let reordered = structuredDraft(contentJSON: reorderedEditorBlocksJSON)
        let service = MockCardEditingService()
        service.createResults = [
            .failure(.transport(code: "response_timeout")),
            .success(
                snapshot(
                    id: "ast_created",
                    title: nil,
                    content: "Server fallback projects Body twice",
                    contentJSON: serverEnvelopeJSON,
                    tags: []
                )
            ),
        ]
        let store = makeNewStore(draft: frozen, service: service)

        let firstSave = await store.save()
        XCTAssertFalse(firstSave)
        XCTAssertTrue(
            store.applyBodyRevision(
                content: reordered.content,
                contentJSON: reordered.contentJSON,
                revision: 0
            )
        )

        let didRetry = await store.retry()

        XCTAssertTrue(didRetry)
        XCTAssertEqual(
            service.createRequests.map(\.draft.contentJSON),
            [editorBlocksJSON, editorBlocksJSON]
        )
        XCTAssertEqual(store.draft.contentJSON, reorderedEditorBlocksJSON)
        XCTAssertEqual(
            store.lastCommittedDraft?.contentJSON,
            serverEnvelopeJSON
        )
        XCTAssertFalse(store.isDirty)
    }

    func testUpdateRetryReusesExactRawJSONForCommitEquivalentCurrentDraft() async {
        let frozen = structuredDraft(contentJSON: editorBlocksJSON)
        let reordered = structuredDraft(contentJSON: reorderedEditorBlocksJSON)
        let service = MockCardEditingService()
        service.updateResults = [
            .failure(.transport(code: "response_timeout")),
            .success(
                snapshot(
                    title: nil,
                    content: "Server fallback projects Body twice",
                    contentJSON: serverEnvelopeJSON,
                    tags: []
                )
            ),
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: structuredDraft(content: "Before", contentJSON: nil),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(frozen, bodyRevision: 1)

        let firstSave = await store.save()
        XCTAssertFalse(firstSave)
        XCTAssertTrue(
            store.applyBodyRevision(
                content: reordered.content,
                contentJSON: reordered.contentJSON,
                revision: 1
            )
        )

        let didRetry = await store.retry()

        XCTAssertTrue(didRetry)
        XCTAssertEqual(
            service.updateRequests.map(\.draft.contentJSON),
            [editorBlocksJSON, editorBlocksJSON]
        )
        XCTAssertEqual(store.draft.contentJSON, reorderedEditorBlocksJSON)
        XCTAssertEqual(
            store.lastCommittedDraft?.contentJSON,
            serverEnvelopeJSON
        )
        XCTAssertFalse(store.isDirty)
    }

    func testStageBackgroundBeforeCardIDOnlyChangesLocalPreview() {
        let service = MockCardEditingService()
        let store = makeNewStore(service: service)

        store.stageBackground(validImage)

        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
        XCTAssertNil(store.cardID)
        XCTAssertTrue(service.events.isEmpty)
        XCTAssertTrue(store.isDirty)
    }

    func testBackgroundRetryDoesNotCreateDuplicateCard() async {
        let service = MockCardEditingService()
        service.createResults = [
            .success(snapshot(id: "ast_1", title: nil, content: "Body", tags: []))
        ]
        service.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed")),
            .success("med_1")
        ]
        let store = makeNewStore(service: service)
        store.stageBackground(validImage)

        let firstSave = await store.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(store.cardID, "ast_1")
        XCTAssertEqual(service.createRequests.count, 1)
        XCTAssertEqual(service.replaceBackgroundRequests.count, 1)
        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
        XCTAssertEqual(store.failureStage, .replacingBackground)

        let retrySucceeded = await store.retry()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(service.createRequests.count, 1)
        XCTAssertEqual(service.updateRequests.count, 0)
        XCTAssertEqual(service.replaceBackgroundRequests.count, 2)
        XCTAssertEqual(store.backgroundMediaRef, "med_1")
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertFalse(store.isDirty)
    }

    func testStagingBackgroundAfterCreateFailureKeepsDraftRetryable() async {
        let service = MockCardEditingService()
        service.createResults = [
            .failure(.transport(code: "offline")),
            .success(snapshot(id: "ast_1", title: nil, content: "Body", tags: []))
        ]
        service.replaceBackgroundResults = [.success("med_1")]
        let store = makeNewStore(service: service)

        _ = await store.save()
        store.stageBackground(validImage)

        XCTAssertEqual(store.failureStage, .creatingCard)
        XCTAssertEqual(store.phase, .failed(.transport(code: "offline")))
        let retried = await store.retry()
        XCTAssertTrue(retried)
        XCTAssertEqual(service.createRequests.count, 2)
        XCTAssertEqual(store.backgroundMediaRef, "med_1")
    }

    func testCreateRetryReusesLifecycleRequestIDAndExactDraftAfterMutation() async {
        let initial = CardEditingDraft(
            title: nil,
            content: "Initial",
            tags: ["idea"],
            isPublic: false
        )
        let revised = CardEditingDraft(
            title: nil,
            content: "Revised while offline",
            tags: ["idea", "work"],
            isPublic: false
        )
        let service = MockCardEditingService()
        service.createResults = [
            .failure(.transport(code: "response_timeout")),
            .success(snapshot(id: "ast_1", title: nil, content: "Initial", tags: ["idea"]))
        ]
        service.updateResults = [
            .success(
                snapshot(
                    id: "ast_1",
                    title: nil,
                    content: revised.content,
                    tags: revised.tags
                )
            )
        ]
        let store = CardEditingStore(
            cardID: nil,
            draft: initial,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        guard let lifecycleRequestID = store.createRequestID else {
            XCTFail("New card lifecycle did not generate a create request ID")
            return
        }

        let firstSave = await store.save()
        XCTAssertFalse(firstSave)
        store.updateDraft(revised, bodyRevision: 1)

        let retryResult = await store.retry()

        XCTAssertFalse(retryResult)
        XCTAssertEqual(service.createRequests.map(\.createRequestID), [
            lifecycleRequestID,
            lifecycleRequestID
        ])
        XCTAssertEqual(service.createRequests.map(\.draft), [initial, initial])
        XCTAssertEqual(store.cardID, "ast_1")
        XCTAssertNil(store.createRequestID)
        XCTAssertEqual(store.draft, revised)
        XCTAssertTrue(store.isDirty)

        let finalSave = await store.save()
        XCTAssertTrue(finalSave)
        XCTAssertEqual(service.updateRequests.map(\.draft), [revised])
        XCTAssertFalse(store.isDirty)
    }

    func testEnsurePersistedReturnsCreatedIDWithoutOwningPickerPresentation() async {
        let service = MockCardEditingService()
        service.createResults = [
            .success(snapshot(id: "ast_created", title: nil, content: "Body", tags: []))
        ]
        let store = makeNewStore(service: service)

        let cardID = await store.ensurePersisted()

        XCTAssertEqual(cardID, "ast_created")
        XCTAssertEqual(service.events, [.create(store.draft)])
        XCTAssertTrue(service.createLinkRequests.isEmpty)
    }

    func testLinkCreationFollowsSuccessfulPrerequisitePersistence() async {
        let service = MockCardEditingService()
        service.createResults = [
            .success(snapshot(id: "ast_created", title: nil, content: "Body", tags: []))
        ]
        service.createLinkResults = [.success(())]
        let store = makeNewStore(service: service)

        if let sourceID = await store.ensurePersisted() {
            _ = await store.createLink(
                CardEditingLink(
                    sourceCardID: sourceID,
                    targetCardID: "ast_target",
                    title: "Target"
                )
            )
        }

        XCTAssertEqual(
            service.events,
            [
                .create(store.draft),
                .createLink(sourceCardID: "ast_created", targetCardID: "ast_target")
            ]
        )
        XCTAssertEqual(store.links.map(\.targetCardID), ["ast_target"])
    }

    func testFailedPrerequisiteSaveDoesNotCreateLink() async {
        let service = MockCardEditingService()
        service.createResults = [.failure(.transport(code: "offline"))]
        service.createLinkResults = [.success(())]
        let store = makeNewStore(service: service)

        if let sourceID = await store.ensurePersisted() {
            _ = await store.createLink(
                CardEditingLink(
                    sourceCardID: sourceID,
                    targetCardID: "ast_target",
                    title: "Target"
                )
            )
        }

        XCTAssertNil(store.cardID)
        XCTAssertEqual(service.createRequests.count, 1)
        XCTAssertTrue(service.createLinkRequests.isEmpty)
        XCTAssertEqual(store.phase, .failed(.transport(code: "offline")))
    }

    func testEnsurePersistedKeepsPendingBackgroundFailureVisible() async {
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed"))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        XCTAssertTrue(store.stageBackground(validImage))
        _ = await store.save()

        let persistedID = await store.ensurePersisted()

        XCTAssertEqual(persistedID, "ast_1")
        XCTAssertEqual(store.failureStage, .replacingBackground)
        XCTAssertEqual(store.phase, .failed(.transport(code: "upload_failed")))
        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
    }

    func testLaterBodyRevisionRemainsDirtyAfterEarlierSaveCompletes() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.updateGate = gate
        let revisionOne = CardEditingDraft(
            title: nil,
            content: "Revision one",
            contentJSON: #"[{"type":"paragraph","content":"Revision one"}]"#,
            tags: [],
            isPublic: false
        )
        let revisionTwo = CardEditingDraft(
            title: nil,
            content: "Revision two",
            contentJSON: #"[{"type":"paragraph","content":"Revision two"}]"#,
            tags: [],
            isPublic: false
        )
        service.updateResults = [
            .success(snapshot(content: revisionOne.content, contentJSON: revisionOne.contentJSON, tags: []))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Initial", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(revisionOne, bodyRevision: 1)

        let saveTask = Task { await store.save() }
        await waitForStore { service.updateRequests.count == 1 }
        store.updateDraft(revisionTwo, bodyRevision: 2)
        await gate.open()

        let saveSucceeded = await saveTask.value
        XCTAssertFalse(saveSucceeded)
        XCTAssertEqual(store.draft, revisionTwo)
        XCTAssertEqual(store.bodyRevision, 2)
        XCTAssertEqual(store.lastCommittedBodyRevision, 1)
        XCTAssertEqual(store.lastCommittedDraft?.content, "Revision one")
        XCTAssertTrue(store.isDirty)
    }

    func testApplyBodyRevisionRejectsStaleBodyWithoutMutatingDraft() {
        let service = MockCardEditingService()
        let initial = CardEditingDraft(
            title: "Hidden legacy title",
            content: "Current body",
            contentJSON: #"[{"type":"paragraph","content":"Current body"}]"#,
            editorAtmosphere: "paper",
            tags: ["idea", "work"],
            isPublic: true
        )
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: initial,
            bodyRevision: 4,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        let applied = store.applyBodyRevision(
            content: "Stale body",
            contentJSON: #"[{"type":"paragraph","content":"Stale body"}]"#,
            revision: 3
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(store.draft, initial)
        XCTAssertEqual(store.bodyRevision, 4)
    }

    func testApplyBodyRevisionAtomicallyPreservesNilTitleAndMetadata() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: "Before",
                contentJSON: #"[{"type":"paragraph","content":"Before"}]"#,
                editorAtmosphere: "linen",
                tags: ["idea", "work"],
                isPublic: true
            ),
            bodyRevision: 1,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        let applied = store.applyBodyRevision(
            content: "After",
            contentJSON: #"[{"type":"heading","content":"After"}]"#,
            revision: 2
        )

        XCTAssertTrue(applied)
        XCTAssertNil(store.draft.title)
        XCTAssertEqual(store.draft.content, "After")
        XCTAssertEqual(
            store.draft.contentJSON,
            #"[{"type":"heading","content":"After"}]"#
        )
        XCTAssertEqual(store.draft.editorAtmosphere, "linen")
        XCTAssertEqual(store.draft.tags, ["idea", "work"])
        XCTAssertTrue(store.draft.isPublic)
        XCTAssertEqual(store.bodyRevision, 2)
    }

    func testApplyBodyRevisionPreservesHiddenLegacyTitleAtExactRevision() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: "  Hidden legacy title  ",
                content: "Bridge event body",
                contentJSON: #"[{"type":"paragraph","content":"Bridge event body"}]"#,
                tags: [],
                isPublic: false
            ),
            bodyRevision: 7,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        let applied = store.applyBodyRevision(
            content: "Snapshot body",
            contentJSON: #"[{"type":"paragraph","content":"Snapshot body"}]"#,
            revision: 7
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(store.draft.title, "  Hidden legacy title  ")
        XCTAssertEqual(store.draft.content, "Snapshot body")
        XCTAssertEqual(store.bodyRevision, 7)
    }

    func testApplyBodyRevisionDuringSaveKeepsNewerBodyDirty() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.updateGate = gate
        service.updateResults = [
            .success(
                snapshot(
                    title: "Hidden legacy title",
                    content: "Revision one",
                    contentJSON: #"[{"type":"paragraph","content":"Revision one"}]"#,
                    editorAtmosphere: "paper",
                    tags: ["idea"],
                    isPublic: true
                )
            )
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: "Hidden legacy title",
                content: "Initial",
                editorAtmosphere: "paper",
                tags: ["idea"],
                isPublic: true
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Revision one",
                contentJSON: #"[{"type":"paragraph","content":"Revision one"}]"#,
                revision: 1
            )
        )

        let saveTask = Task { await store.save() }
        await waitForStore { service.updateRequests.count == 1 }
        XCTAssertTrue(
            store.applyBodyRevision(
                content: "Revision two",
                contentJSON: #"[{"type":"paragraph","content":"Revision two"}]"#,
                revision: 2
            )
        )
        await gate.open()

        let saveSucceeded = await saveTask.value
        XCTAssertFalse(saveSucceeded)
        XCTAssertEqual(store.draft.title, "Hidden legacy title")
        XCTAssertEqual(store.draft.content, "Revision two")
        XCTAssertEqual(store.draft.editorAtmosphere, "paper")
        XCTAssertEqual(store.draft.tags, ["idea"])
        XCTAssertTrue(store.draft.isPublic)
        XCTAssertEqual(store.bodyRevision, 2)
        XCTAssertEqual(store.lastCommittedBodyRevision, 1)
        XCTAssertTrue(store.isDirty)
    }

    func testInlineImageUploadReturnsInsertableReferenceWithoutMutatingBody() async throws {
        let service = MockCardEditingService()
        let expected = CardEditingInlineImageUpload(
            mediaRef: "med_inline_1",
            url: try XCTUnwrap(URL(string: "https://cdn.example.com/inline.png"))
        )
        service.inlineImageUploadResults = [.success(expected)]
        let store = makeNewStore(service: service)
        let originalDraft = store.draft
        let originalRevision = store.bodyRevision

        let uploaded = try await store.uploadInlineImage(validImage)

        XCTAssertEqual(uploaded, expected)
        XCTAssertEqual(service.inlineImageUploadRequests, [validImage])
        XCTAssertEqual(store.draft, originalDraft)
        XCTAssertEqual(store.bodyRevision, originalRevision)
    }

    func testInlineImageUploadFailureDoesNotMutateBody() async {
        let service = MockCardEditingService()
        service.inlineImageUploadResults = [
            .failure(.transport(code: "card_inline_image_url_missing"))
        ]
        let store = makeNewStore(service: service)
        let originalDraft = store.draft
        let originalRevision = store.bodyRevision

        do {
            _ = try await store.uploadInlineImage(validImage)
            XCTFail("Expected inline image upload to fail")
        } catch {
            XCTAssertEqual(
                error as? CardEditingError,
                .transport(code: "card_inline_image_url_missing")
            )
        }

        XCTAssertEqual(service.inlineImageUploadRequests, [validImage])
        XCTAssertEqual(store.draft, originalDraft)
        XCTAssertEqual(store.bodyRevision, originalRevision)
    }

    func testHydrateDuringCreateRetainsCanonicalIDAndNextSaveUpdates() async throws {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.createGate = gate
        service.createResults = [
            .success(snapshot(id: "ast_created", title: nil, content: "Initial", tags: [])),
            .success(snapshot(id: "ast_duplicate", title: nil, content: "Hydrated later", tags: []))
        ]
        let hydrated = CardEditingDraft(
            title: nil,
            content: "Hydrated later",
            tags: [],
            isPublic: false
        )
        service.updateResults = [
            .success(snapshot(id: "ast_created", title: nil, content: "Hydrated later", tags: []))
        ]
        let store = makeNewStore(
            draft: .init(title: nil, content: "Initial", tags: [], isPublic: false),
            service: service
        )

        let createTask = Task { await store.save() }
        await waitForStore { service.createRequests.count == 1 }
        store.hydrate(
            draft: hydrated,
            bodyRevision: 1,
            backgroundMediaRef: nil,
            links: []
        )
        let overlappingSave = Task { await store.save() }
        let overlappingResult = await overlappingSave.value

        XCTAssertFalse(overlappingResult)
        XCTAssertEqual(service.createRequests.count, 1)
        await gate.open()

        let createCompleted = await createTask.value
        XCTAssertFalse(createCompleted)
        let canonicalID = try XCTUnwrap(store.cardID)
        XCTAssertEqual(canonicalID, "ast_created")
        XCTAssertEqual(store.draft, hydrated)
        XCTAssertTrue(store.isDirty)

        let updated = await store.save()
        XCTAssertTrue(updated)
        XCTAssertEqual(service.createRequests.count, 1)
        XCTAssertEqual(service.updateRequests.count, 1)
    }

    func testHydrateDuringUpdateKeepsOperationBusyAndConfirmedWriteDirty() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.updateGate = gate
        let initial = CardEditingDraft(
            title: nil,
            content: "Initial",
            tags: [],
            isPublic: false
        )
        let submitted = CardEditingDraft(
            title: nil,
            content: "Submitted",
            tags: [],
            isPublic: false
        )
        let hydrated = CardEditingDraft(
            title: nil,
            content: "Hydrated later",
            tags: [],
            isPublic: false
        )
        service.updateResults = [
            .success(snapshot(content: submitted.content, tags: [])),
            .success(snapshot(content: hydrated.content, tags: []))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: initial,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(submitted, bodyRevision: 1)

        let updateTask = Task { await store.save() }
        await waitForStore { service.updateRequests.count == 1 }
        store.hydrate(
            draft: hydrated,
            bodyRevision: 2,
            backgroundMediaRef: nil,
            links: []
        )

        XCTAssertEqual(store.phase, .saving)
        let overlappingSave = await store.save()
        XCTAssertFalse(overlappingSave)
        XCTAssertEqual(service.updateRequests.count, 1)
        await gate.open()

        let firstSave = await updateTask.value
        XCTAssertFalse(firstSave)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.draft, hydrated)
        XCTAssertEqual(store.lastCommittedDraft?.content, submitted.content)
        XCTAssertEqual(store.lastCommittedBodyRevision, 1)
        XCTAssertTrue(store.isDirty)

        let secondSave = await store.save()
        XCTAssertTrue(secondSave)
        XCTAssertEqual(service.updateRequests.count, 2)
        XCTAssertFalse(store.isDirty)
    }

    func testHydrateDuringBackgroundWriteKeepsOperationBusyAndRecordsSuccess() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.replaceBackgroundGate = gate
        service.replaceBackgroundResults = [.success("med_uploaded")]
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            tags: [],
            isPublic: false
        )
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: draft,
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        store.stageBackground(validImage)

        let saveTask = Task { await store.save() }
        await waitForStore { service.replaceBackgroundRequests.count == 1 }
        store.hydrate(
            draft: draft,
            backgroundMediaRef: "med_hydrated",
            links: []
        )

        XCTAssertEqual(store.phase, .updatingBackground)
        let overlappingSave = await store.save()
        XCTAssertFalse(overlappingSave)
        XCTAssertEqual(service.replaceBackgroundRequests.count, 1)
        await gate.open()

        let saveSucceeded = await saveTask.value
        XCTAssertTrue(saveSucceeded)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.backgroundMediaRef, "med_uploaded")
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertFalse(store.isDirty)
    }

    func testHydrateDuringBackgroundFailurePreservesPendingIntentAndRetry() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.replaceBackgroundGate = gate
        service.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed")),
            .success("med_uploaded")
        ]
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            tags: [],
            isPublic: false
        )
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: draft,
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        _ = store.stageBackground(validImage)

        let saveTask = Task { await store.save() }
        await waitForStore { service.replaceBackgroundRequests.count == 1 }
        store.hydrate(
            draft: draft,
            backgroundMediaRef: "med_hydrated",
            links: []
        )
        await gate.open()

        let firstSave = await saveTask.value
        XCTAssertFalse(firstSave)
        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
        XCTAssertEqual(store.failureStage, .replacingBackground)
        XCTAssertEqual(store.phase, .failed(.transport(code: "upload_failed")))

        let retried = await store.retry()
        XCTAssertTrue(retried)
        XCTAssertEqual(service.replaceBackgroundRequests, [validImage, validImage])
        XCTAssertEqual(store.backgroundMediaRef, "med_uploaded")
        XCTAssertEqual(store.backgroundIntent, .unchanged)
    }

    func testBackgroundRetryUsesCapturedImageAfterNewImageIsStaged() async {
        let replacement = CardEditingImage(
            data: Data("replacement".utf8),
            filename: "replacement.png",
            mimeType: "image/png"
        )
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed")),
            .success("med_original")
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        XCTAssertTrue(store.stageBackground(validImage))
        _ = await store.save()

        XCTAssertTrue(store.stageBackground(replacement))
        let retried = await store.retry()

        XCTAssertFalse(retried)
        XCTAssertEqual(service.replaceBackgroundRequests, [validImage, validImage])
        XCTAssertEqual(store.backgroundMediaRef, "med_original")
        XCTAssertEqual(store.backgroundIntent, .replace(replacement))
        XCTAssertTrue(store.isDirty)
    }

    func testStageBackgroundRemovalDefersDeleteUntilSave() async {
        let service = MockCardEditingService()
        service.removeBackgroundResults = [.success(())]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )

        store.stageBackgroundRemoval()

        XCTAssertEqual(store.backgroundIntent, .remove)
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(service.removeBackgroundRequests.isEmpty)

        let saved = await store.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(service.removeBackgroundRequests, ["ast_1"])
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertFalse(store.isDirty)
    }

    func testRemovalWithoutCommittedBackgroundCancelsLocalReplacement() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        XCTAssertTrue(store.stageBackground(validImage))

        store.stageBackgroundRemoval()

        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(service.events.isEmpty)
    }

    func testRestoreClearsStagedMutationAndKeepsCommittedReference() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        store.stageBackgroundRemoval()

        XCTAssertTrue(store.restoreBackground())

        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(service.events.isEmpty)
    }

    func testRestoreAfterFailedReplacementPreservesUncertainWriteAndExactRetry() async {
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [
            .failure(.transport(code: "response_timeout")),
            .success("med_retried"),
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        XCTAssertTrue(store.stageBackground(validImage))
        let saved = await store.save()
        XCTAssertFalse(saved)

        XCTAssertFalse(store.restoreBackground())

        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertEqual(store.failureStage, .replacingBackground)
        XCTAssertEqual(store.phase, .failed(.transport(code: "response_timeout")))
        XCTAssertTrue(store.isDirty)

        let retried = await store.retry()

        XCTAssertTrue(retried)
        XCTAssertEqual(service.replaceBackgroundRequests, [validImage, validImage])
        XCTAssertEqual(store.backgroundMediaRef, "med_retried")
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertFalse(store.isDirty)
    }

    func testReplacementSupersedesStagedRemoval() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        store.stageBackgroundRemoval()

        XCTAssertTrue(store.stageBackground(validImage))

        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertTrue(service.events.isEmpty)
    }

    func testRemovalFailureKeepsCommittedReferenceAndRemovalIntent() async {
        let service = MockCardEditingService()
        service.removeBackgroundResults = [
            .failure(.transport(code: "remove_failed")),
            .success(()),
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        store.stageBackgroundRemoval()

        let firstSave = await store.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertEqual(store.backgroundIntent, .remove)
        XCTAssertEqual(store.failureStage, .removingBackground)

        let retried = await store.retry()
        XCTAssertTrue(retried)
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(store.backgroundIntent, .unchanged)
    }

    func testRestoreAfterFailedRemovalPreservesUncertainWriteAndExactRetry() async {
        let service = MockCardEditingService()
        service.removeBackgroundResults = [
            .failure(.transport(code: "response_timeout")),
            .success(()),
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        store.stageBackgroundRemoval()
        let saved = await store.save()
        XCTAssertFalse(saved)

        XCTAssertFalse(store.restoreBackground())

        XCTAssertEqual(store.backgroundIntent, .remove)
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertEqual(store.failureStage, .removingBackground)
        XCTAssertEqual(store.phase, .failed(.transport(code: "response_timeout")))
        XCTAssertTrue(store.isDirty)

        let retried = await store.retry()

        XCTAssertTrue(retried)
        XCTAssertEqual(service.removeBackgroundRequests, ["ast_1", "ast_1"])
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertFalse(store.isDirty)
    }

    func testRemoveAfterUncertainReplacementWithoutOriginalStagesCompensation() async {
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [
            .failure(.transport(code: "response_timeout")),
            .success("med_retried"),
        ]
        service.removeBackgroundResults = [.success(())]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        XCTAssertTrue(store.stageBackground(validImage))
        let initialSave = await store.save()
        XCTAssertFalse(initialSave)

        store.stageBackgroundRemoval()

        XCTAssertEqual(store.backgroundIntent, .remove)
        XCTAssertEqual(store.failureStage, .replacingBackground)
        XCTAssertTrue(store.isDirty)

        let recoveredFrozenWrite = await store.retry()
        XCTAssertFalse(recoveredFrozenWrite)
        XCTAssertEqual(
            service.replaceBackgroundRequests,
            [validImage, validImage]
        )
        XCTAssertEqual(store.backgroundIntent, .remove)
        XCTAssertNil(store.failureStage)
        XCTAssertTrue(store.isDirty)

        let compensated = await store.save()
        XCTAssertTrue(compensated)
        XCTAssertEqual(service.removeBackgroundRequests, ["ast_1"])
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        XCTAssertFalse(store.isDirty)
    }

    func testRemovalRetryPreservesNewerReplacementIntent() async {
        let replacement = CardEditingImage(
            data: Data("replacement".utf8),
            filename: "replacement.png",
            mimeType: "image/png"
        )
        let service = MockCardEditingService()
        service.removeBackgroundResults = [
            .failure(.transport(code: "remove_failed")),
            .success(()),
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        store.stageBackgroundRemoval()
        let saved = await store.save()
        XCTAssertFalse(saved)
        XCTAssertTrue(store.stageBackground(replacement))

        let retried = await store.retry()
        XCTAssertFalse(retried)

        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(store.backgroundIntent, .replace(replacement))
        XCTAssertTrue(store.isDirty)
    }

    func testHydrateReplacesCanonicalEditorStateWithoutCallingService() {
        let json = #"[{"id":"b1","type":"paragraph","content":"Server body"}]"#
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Old", tags: [], isPublic: false),
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )

        store.hydrate(
            draft: .init(
                title: "Canonical",
                content: "Server body",
                contentJSON: json,
                editorAtmosphere: "rain",
                tags: ["#idea", " idea ", "work"],
                isPublic: true
            ),
            backgroundMediaRef: "med_server",
            links: [link]
        )

        XCTAssertEqual(
            store.draft,
            .init(
                title: "Canonical",
                content: "Server body",
                contentJSON: json,
                editorAtmosphere: "rain",
                tags: ["idea", "work"],
                isPublic: true
            )
        )
        XCTAssertEqual(store.backgroundMediaRef, "med_server")
        XCTAssertEqual(store.links, [link])
        XCTAssertEqual(store.phase, .ready)
        XCTAssertTrue(service.createRequests.isEmpty)
        XCTAssertTrue(service.updateRequests.isEmpty)
    }

    func testUpdateDraftNormalizesTagsWithoutCallingService() {
        let json = #"[{"id":"b1","type":"paragraph","content":"Typed body"}]"#
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Old", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        store.updateDraft(
            .init(
                title: "Local",
                content: "Typed body",
                contentJSON: json,
                editorAtmosphere: "dawn",
                tags: ["#one", " one ", "two"],
                isPublic: false
            )
        )

        XCTAssertEqual(store.draft.tags, ["one", "two"])
        XCTAssertEqual(store.draft.content, "Typed body")
        XCTAssertEqual(store.draft.contentJSON, json)
        XCTAssertEqual(store.draft.editorAtmosphere, "dawn")
        XCTAssertTrue(service.createRequests.isEmpty)
        XCTAssertTrue(service.updateRequests.isEmpty)
    }

    func testTagEditDoesNotDiscardStructuredDocument() {
        let json = #"[{"id":"b1","type":"paragraph","content":"Body"}]"#
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: "Body",
                contentJSON: json,
                editorAtmosphere: "rain",
                tags: ["idea"],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        store.updateDraft(
            .init(
                title: nil,
                content: store.draft.content,
                contentJSON: store.draft.contentJSON,
                editorAtmosphere: store.draft.editorAtmosphere,
                tags: ["#idea", " work "],
                isPublic: store.draft.isPublic
            )
        )

        XCTAssertEqual(store.draft.contentJSON, json)
        XCTAssertEqual(store.draft.editorAtmosphere, "rain")
        XCTAssertEqual(store.draft.tags, ["idea", "work"])
        XCTAssertTrue(service.createRequests.isEmpty)
        XCTAssertTrue(service.updateRequests.isEmpty)
    }

    func testHydrateThenTagEditCapturesStructuredFieldsInUpdate() async {
        let json = #"[{"id":"b1","type":"paragraph","content":"Body"}]"#
        let service = MockCardEditingService()
        service.updateResults = [
            .success(
                snapshot(
                    content: "Body",
                    contentJSON: json,
                    editorAtmosphere: "rain",
                    tags: ["idea", "work"]
                )
            )
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Legacy", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.hydrate(
            draft: .init(
                title: "Canonical",
                content: "Body",
                contentJSON: json,
                editorAtmosphere: "rain",
                tags: ["idea"],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: []
        )
        store.updateDraft(
            store.draft.updatingMetadataAndFallback(
                title: store.draft.title,
                content: store.draft.content,
                tags: ["idea", "work"],
                isPublic: store.draft.isPublic
            )
        )

        let saved = await store.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(service.updateRequests.count, 1)
        XCTAssertEqual(service.updateRequests[0].draft.contentJSON, json)
        XCTAssertEqual(service.updateRequests[0].draft.editorAtmosphere, "rain")
        XCTAssertEqual(service.updateRequests[0].draft.tags, ["idea", "work"])
    }

    func testReplaceLinksPreservesUnsavedDraftAndStagedBackground() {
        let service = MockCardEditingService()
        let initial = CardEditingDraft(
            title: nil,
            content: "Initial",
            tags: [],
            isPublic: false
        )
        let revised = CardEditingDraft(
            title: nil,
            content: "Unsaved",
            tags: ["idea"],
            isPublic: false
        )
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Related"
        )
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: initial,
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        store.updateDraft(revised, bodyRevision: 1)
        store.stageBackground(validImage)

        store.replaceLinks([link])

        XCTAssertEqual(store.links, [link])
        XCTAssertEqual(store.draft, revised)
        XCTAssertEqual(store.lastCommittedDraft, initial)
        XCTAssertEqual(store.backgroundIntent, .replace(validImage))
        XCTAssertEqual(store.backgroundMediaRef, "med_old")
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(service.events.isEmpty)
    }

    func testSaveFailureKeepsNormalizedDraftForExactRetry() async {
        let json = #"[{"id":"b1","type":"paragraph","content":"Revised"}]"#
        let service = MockCardEditingService()
        service.updateResults = [
            .failure(.transport(code: "offline")),
            .success(
                snapshot(
                    content: "Revised",
                    contentJSON: json,
                    editorAtmosphere: "rain",
                    tags: ["idea", "work"]
                )
            )
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: "Revised",
                content: "Revised",
                contentJSON: json,
                editorAtmosphere: "rain",
                tags: ["#idea", " work ", "idea", "", "extra"],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(store.draft, bodyRevision: 1)

        _ = await store.save()

        XCTAssertEqual(store.draft.tags, ["idea", "work", "extra"])
        XCTAssertEqual(service.updateRequests.count, 1)
        XCTAssertEqual(service.updateRequests[0].draft, store.draft)

        let laterDraft = store.draft.updatingMetadataAndFallback(
            title: store.draft.title,
            content: store.draft.content,
            tags: store.draft.tags + ["later"],
            isPublic: store.draft.isPublic
        )
        store.updateDraft(laterDraft, bodyRevision: 2)

        let retryResult = await store.retry()

        XCTAssertFalse(retryResult)
        XCTAssertEqual(service.updateRequests.count, 2)
        XCTAssertEqual(service.updateRequests[0], service.updateRequests[1])
        XCTAssertEqual(store.draft.contentJSON, json)
        XCTAssertEqual(store.draft.editorAtmosphere, "rain")
        XCTAssertEqual(store.draft.tags, ["idea", "work", "extra", "later"])
        XCTAssertTrue(store.isDirty)
        XCTAssertNil(store.draft.validationError)
    }

    func testSaveAcceptsObjectStructuredDocument() async {
        let json = #"{"blocks":[{"type":"paragraph","content":"Body"}]}"#
        let service = MockCardEditingService()
        service.updateResults = [
            .success(
                snapshot(
                    content: "Body",
                    contentJSON: json,
                    editorAtmosphere: "none",
                    tags: []
                )
            )
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: "Body",
                contentJSON: json,
                editorAtmosphere: "none",
                tags: [],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(store.draft, bodyRevision: 1)

        _ = await store.save()

        XCTAssertEqual(service.updateRequests.count, 1)
        XCTAssertEqual(service.updateRequests[0].draft.contentJSON, json)
        XCTAssertNil(store.draft.validationError)
    }

    func testDraftRejectsMalformedStructuredDocument() {
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            contentJSON: #"[{"type":"paragraph"}"#,
            editorAtmosphere: "none",
            tags: [],
            isPublic: false
        )

        XCTAssertEqual(
            draft.validationError,
            .invalidDraft(code: "invalid_content_json")
        )
    }

    func testDraftRejectsScalarStructuredDocument() {
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            contentJSON: #""Body""#,
            editorAtmosphere: "none",
            tags: [],
            isPublic: false
        )

        XCTAssertEqual(
            draft.validationError,
            .invalidDraft(code: "invalid_content_json")
        )
    }

    func testDraftRejectsEmptyFallbackAndStructuredBody() {
        let draft = CardEditingDraft(
            title: nil,
            content: " \n ",
            contentJSON: "  ",
            editorAtmosphere: "none",
            tags: [],
            isPublic: false
        )

        XCTAssertNil(draft.contentJSON)
        XCTAssertEqual(
            draft.validationError,
            .invalidDraft(code: "empty_content")
        )
    }

    func testSaveRejectsInvalidStructuredDocumentWithoutCallingService() async {
        let service = MockCardEditingService()
        service.updateResults = [.success(snapshot(content: "Body", tags: []))]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: "Body",
                contentJSON: #"42"#,
                editorAtmosphere: "none",
                tags: [],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        _ = await store.save()

        XCTAssertEqual(
            store.phase,
            .failed(.invalidDraft(code: "invalid_content_json"))
        )
        XCTAssertTrue(service.updateRequests.isEmpty)
    }

    func testSaveRejectsEmptyFallbackAndStructuredBodyWithoutCallingService() async {
        let service = MockCardEditingService()
        service.updateResults = [.success(snapshot(content: "Unexpected", tags: []))]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: nil,
                content: " \n ",
                contentJSON: nil,
                editorAtmosphere: "none",
                tags: [],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        _ = await store.save()

        XCTAssertEqual(
            store.phase,
            .failed(.invalidDraft(code: "empty_content"))
        )
        XCTAssertTrue(service.updateRequests.isEmpty)
    }

    func testDeleteLinkFailureRetainsLinkUntilCanonicalSuccess() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.deleteLinkResults = [
            .failure(.transport(code: "offline")),
            .success(())
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [link],
            service: service
        )

        _ = await store.deleteLink(link)
        XCTAssertEqual(store.links, [link])

        _ = await store.deleteLink(link)
        XCTAssertTrue(store.links.isEmpty)
        XCTAssertEqual(service.deleteLinkRequests, [link, link])
    }

    func testDeleteLinkAllowsEditedCardToBeTargetOfCanonicalEdge() async {
        let incomingLink = CardEditingLink(
            sourceCardID: "ast_source",
            targetCardID: "ast_editing",
            title: "Incoming companion"
        )
        let service = MockCardEditingService()
        service.deleteLinkResults = [.success(())]
        let store = CardEditingStore(
            cardID: "ast_editing",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [incomingLink],
            service: service
        )

        let deleted = await store.deleteLink(incomingLink)

        XCTAssertTrue(deleted)
        XCTAssertEqual(service.deleteLinkRequests, [incomingLink])
        XCTAssertTrue(store.links.isEmpty)
    }

    func testDeleteLinkRejectsEdgeUnrelatedToEditedCard() async {
        let unrelatedLink = CardEditingLink(
            sourceCardID: "ast_source",
            targetCardID: "ast_target",
            title: "Unrelated companion"
        )
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_editing",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [unrelatedLink],
            service: service
        )

        let deleted = await store.deleteLink(unrelatedLink)

        XCTAssertFalse(deleted)
        XCTAssertTrue(service.deleteLinkRequests.isEmpty)
        XCTAssertEqual(store.links, [unrelatedLink])
    }

    func testCreateLinkFailureDoesNotPublishLocalRelationship() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.createLinkResults = [
            .failure(.transport(code: "conflict")),
            .success(())
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        _ = await store.createLink(link)
        XCTAssertTrue(store.links.isEmpty)

        _ = await store.createLink(link)
        XCTAssertEqual(store.links, [link])
        XCTAssertEqual(service.createLinkRequests, [link, link])
    }

    func testReconcileFailedCreateLinkReadsCommittedCanonicalLinkAfterLostResponse() async {
        let existing = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_existing",
            title: "Existing"
        )
        let failed = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_missing",
            title: "Missing"
        )
        let service = MockCardEditingService()
        service.createLinkResults = [
            .failure(.transport(code: "card_editing_timeout"))
        ]
        service.fetchLinksResults = [.success([existing, failed])]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [existing],
            service: service
        )
        _ = await store.createLink(failed)

        let reconciled = await store.reconcileFailedRelationshipMutation()

        XCTAssertTrue(reconciled)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.links, [existing, failed])
        XCTAssertEqual(service.fetchLinksRequests, ["ast_1"])
        let retried = await store.retry()
        XCTAssertFalse(retried)
        XCTAssertEqual(service.createLinkRequests, [failed])
    }

    func testReconcileFailedDeleteLinkReadsCommittedCanonicalAbsenceAfterLostResponse() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.deleteLinkResults = [
            .failure(.transport(code: "card_editing_timeout"))
        ]
        service.fetchLinksResults = [.success([])]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [link],
            service: service
        )
        _ = await store.deleteLink(link)

        let reconciled = await store.reconcileFailedRelationshipMutation()

        XCTAssertTrue(reconciled)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertTrue(store.links.isEmpty)
        XCTAssertEqual(service.fetchLinksRequests, ["ast_1"])
        let retried = await store.retry()
        XCTAssertFalse(retried)
        XCTAssertEqual(service.deleteLinkRequests, [link])
    }

    func testReconcileFailedRelationshipFetchFailureKeepsRetryContext() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.createLinkResults = [
            .failure(.transport(code: "card_editing_timeout")),
            .success(())
        ]
        service.fetchLinksResults = [
            .failure(.transport(code: "card_editing_offline"))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        _ = await store.createLink(link)

        let reconciled = await store.reconcileFailedRelationshipMutation()

        XCTAssertFalse(reconciled)
        XCTAssertEqual(store.failureStage, .creatingLink)
        XCTAssertEqual(
            store.phase,
            .failed(.transport(code: "card_editing_offline"))
        )
        XCTAssertTrue(store.links.isEmpty)
        XCTAssertEqual(service.fetchLinksRequests, ["ast_1"])

        let retried = await store.retry()

        XCTAssertTrue(retried)
        XCTAssertEqual(service.createLinkRequests, [link, link])
        XCTAssertEqual(store.links, [link])
    }

    func testReconcileExplicitCreateLinkNotFoundClearsIntentAfterCanonicalAbsence() async {
        let existing = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_existing",
            title: "Existing"
        )
        let missing = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_missing",
            title: "Missing"
        )
        let service = MockCardEditingService()
        service.createLinkResults = [
            .failure(.transport(code: "card_editing_not_found"))
        ]
        service.fetchLinksResults = [.success([existing])]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [existing],
            service: service
        )
        _ = await store.createLink(missing)

        let reconciled = await store.reconcileFailedRelationshipMutation()

        XCTAssertTrue(reconciled)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.links, [existing])
        XCTAssertEqual(service.fetchLinksRequests, ["ast_1"])
        let retried = await store.retry()
        XCTAssertFalse(retried)
        XCTAssertEqual(service.createLinkRequests, [missing])
    }

    func testReconcileFailedRelationshipMutationRefusesDraftFailure() async {
        let draftService = MockCardEditingService()
        draftService.updateResults = [.failure(.transport(code: "offline"))]
        let draftStore = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Before", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: draftService
        )
        draftStore.updateDraft(
            .init(title: nil, content: "After", tags: [], isPublic: false),
            bodyRevision: 1
        )
        _ = await draftStore.save()

        let reconciled = await draftStore.reconcileFailedRelationshipMutation()
        XCTAssertFalse(reconciled)
        XCTAssertEqual(draftStore.failureStage, .updatingCard)
        XCTAssertEqual(draftStore.phase, .failed(.transport(code: "offline")))
        XCTAssertTrue(draftService.fetchLinksRequests.isEmpty)
    }

    func testReconcileFailedRelationshipMutationRefusesBackgroundFailure() async {
        let backgroundService = MockCardEditingService()
        backgroundService.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed"))
        ]
        let backgroundStore = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: backgroundService
        )
        _ = backgroundStore.stageBackground(validImage)
        _ = await backgroundStore.save()

        let reconciled = await backgroundStore
            .reconcileFailedRelationshipMutation()
        XCTAssertFalse(reconciled)
        XCTAssertEqual(backgroundStore.failureStage, .replacingBackground)
        XCTAssertEqual(
            backgroundStore.phase,
            .failed(.transport(code: "upload_failed"))
        )
        XCTAssertTrue(backgroundService.fetchLinksRequests.isEmpty)
    }

    func testInvalidLinkReplacesOlderRetryContextAtomically() async {
        let failedLink = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let invalidLink = CardEditingLink(
            sourceCardID: "wrong_source",
            targetCardID: "ast_3",
            title: "Invalid"
        )
        let service = MockCardEditingService()
        service.createLinkResults = [.failure(.transport(code: "offline"))]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        _ = await store.createLink(failedLink)

        let invalidResult = await store.createLink(invalidLink)
        let retryResult = await store.retry()

        XCTAssertFalse(invalidResult)
        XCTAssertFalse(retryResult)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(
            store.phase,
            .failed(.invalidDraft(code: "invalid_link_source"))
        )
        XCTAssertEqual(service.createLinkRequests, [failedLink])
    }

    func testInvalidBackgroundDuringSaveDoesNotReplaceActivePhase() async {
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.updateGate = gate
        service.updateResults = [
            .success(snapshot(content: "Revised", tags: []))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Initial", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
        store.updateDraft(
            .init(title: nil, content: "Revised", tags: [], isPublic: false),
            bodyRevision: 1
        )
        let saveTask = Task { await store.save() }
        await waitForStore { service.updateRequests.count == 1 }
        let invalidImage = CardEditingImage(
            data: Data(),
            filename: "empty.png",
            mimeType: "image/png"
        )

        let staged = store.stageBackground(invalidImage)

        XCTAssertFalse(staged)
        XCTAssertEqual(store.phase, .saving)
        XCTAssertNil(store.failureStage)
        XCTAssertEqual(store.backgroundIntent, .unchanged)
        await gate.open()
        let saveSucceeded = await saveTask.value
        XCTAssertTrue(saveSucceeded)
    }

    func testAdoptedLegacyCardIDEnablesCanonicalUnlink() async {
        let link = CardEditingLink(
            sourceCardID: "ast_created",
            targetCardID: "ast_target",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.deleteLinkResults = [.success(())]
        let store = makeNewStore(service: service)

        let adopted = store.adoptCanonicalCardID("ast_created")
        store.replaceLinks([link])
        let deleted = await store.deleteLink(link)

        XCTAssertTrue(adopted)
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.cardID, "ast_created")
        XCTAssertNil(store.createRequestID)
        XCTAssertEqual(service.deleteLinkRequests, [link])
        XCTAssertTrue(store.links.isEmpty)
    }

    func testHydrateDuringLinkFailurePreservesExactRetryPayload() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        let gate = AsyncGate()
        service.createLinkGate = gate
        service.createLinkResults = [
            .failure(.transport(code: "offline")),
            .success(())
        ]
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            tags: [],
            isPublic: false
        )
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: draft,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        let linkTask = Task { await store.createLink(link) }
        await waitForStore { service.createLinkRequests.count == 1 }
        store.hydrate(
            draft: draft,
            backgroundMediaRef: nil,
            links: []
        )
        XCTAssertEqual(store.phase, .linking)
        await gate.open()

        let firstAttempt = await linkTask.value
        XCTAssertFalse(firstAttempt)
        XCTAssertEqual(store.failureStage, .creatingLink)

        let retried = await store.retry()
        XCTAssertTrue(retried)
        XCTAssertEqual(service.createLinkRequests, [link, link])
        XCTAssertEqual(store.links, [link])
    }

    func testBackgroundFailureKeepsCommittedRefUntilRetrySucceeds() async {
        let image = CardEditingImage(
            data: Data("image".utf8),
            filename: "background.png",
            mimeType: "image/png"
        )
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed")),
            .success("med_new")
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )

        store.stageBackground(image)
        _ = await store.save()
        XCTAssertEqual(store.backgroundMediaRef, "med_old")

        _ = await store.retry()
        XCTAssertEqual(store.backgroundMediaRef, "med_new")
        XCTAssertEqual(service.replaceBackgroundRequests.count, 2)
    }

    func testInvalidBackgroundNeverCallsServiceOrReplacesCommittedRef() {
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [.success("med_unexpected")]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        let oversized = CardEditingImage(
            data: Data(count: CardEditingImage.maxBackgroundBytes + 1),
            filename: "background.png",
            mimeType: "image/png"
        )

        store.stageBackground(oversized)

        XCTAssertEqual(
            store.phase,
            .failed(.invalidDraft(code: "invalid_background_image"))
        )
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertTrue(service.replaceBackgroundRequests.isEmpty)
    }

    private var editorBlocksJSON: String {
        #"[{"id":"paragraph-probe","type":"paragraph","props":{"backgroundColor":"default","textColor":"default","textAlignment":"left"},"content":[{"type":"text","text":"Body","styles":{}}],"children":[]}]"#
    }

    private var reorderedEditorBlocksJSON: String {
        #"[{"children":[],"content":[{"styles":{},"text":"Body","type":"text"}],"props":{"textAlignment":"left","backgroundColor":"default","textColor":"default"},"type":"paragraph","id":"paragraph-probe"}]"#
    }

    private var serverEnvelopeJSON: String {
        #"{"tags":[],"title":"Body","blocks":[{"children":[],"content":[{"styles":{},"text":"Body","type":"text"}],"props":{"textAlignment":"left","backgroundColor":"default","textColor":"default"},"type":"paragraph","id":"paragraph-probe"}],"content":"Server fallback projects Body twice","editor_kind":"blocknote","schema_version":1}"#
    }

    private var twoEditorBlocksJSON: String {
        #"[{"id":"first","type":"paragraph","content":[{"type":"text","text":"First","styles":{}}],"children":[]},{"id":"second","type":"paragraph","content":[{"type":"text","text":"Second","styles":{}}],"children":[]}]"#
    }

    private var reversedEditorBlocksJSON: String {
        #"[{"id":"second","type":"paragraph","content":[{"type":"text","text":"Second","styles":{}}],"children":[]},{"id":"first","type":"paragraph","content":[{"type":"text","text":"First","styles":{}}],"children":[]}]"#
    }

    private var changedEditorBlocksJSON: String {
        #"[{"id":"first","type":"paragraph","content":[{"type":"text","text":"Changed","styles":{}}],"children":[]},{"id":"second","type":"paragraph","content":[{"type":"text","text":"Second","styles":{}}],"children":[]}]"#
    }

    private func structuredDraft(
        content: String = "Body",
        contentJSON: String?
    ) -> CardEditingDraft {
        CardEditingDraft(
            title: nil,
            content: content,
            contentJSON: contentJSON,
            tags: [],
            isPublic: false
        )
    }

    private var validImage: CardEditingImage {
        CardEditingImage(
            data: Data("image".utf8),
            filename: "background.png",
            mimeType: "image/png"
        )
    }

    private func makeNewStore(
        draft: CardEditingDraft = .init(
            title: nil,
            content: "Body",
            tags: [],
            isPublic: false
        ),
        service: MockCardEditingService
    ) -> CardEditingStore {
        CardEditingStore(
            cardID: nil,
            draft: draft,
            backgroundMediaRef: nil,
            links: [],
            service: service
        )
    }

    private func snapshot(
        id: String = "ast_1",
        title: String? = "Revised",
        content: String,
        contentJSON: String? = nil,
        editorAtmosphere: String = "none",
        tags: [String],
        isPublic: Bool = false,
        backgroundMediaRef: String? = nil
    ) -> CardEditingSnapshot {
        CardEditingSnapshot(
            id: id,
            title: title,
            content: content,
            contentJSON: contentJSON,
            editorAtmosphere: editorAtmosphere,
            tags: tags,
            isPublic: isPublic,
            backgroundMediaRef: backgroundMediaRef
        )
    }

    private func waitForStore(
        timeoutIterations: Int = 500,
        _ predicate: @escaping () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for card editing store state")
    }

}

private final class MockCardEditingService: CoreCardEditingServing, @unchecked Sendable {
    enum Event: Equatable {
        case create(CardEditingDraft)
        case update(cardID: String, draft: CardEditingDraft)
        case replaceBackground(cardID: String)
        case removeBackground(cardID: String)
        case createLink(sourceCardID: String, targetCardID: String)
        case deleteLink(sourceCardID: String, targetCardID: String)
    }

    struct SaveRequest: Equatable {
        let cardID: String
        let draft: CardEditingDraft
    }

    struct CreateRequest: Equatable {
        let createRequestID: String
        let draft: CardEditingDraft
    }

    var createResults: [Result<CardEditingSnapshot, CardEditingError>] = []
    var updateResults: [Result<CardEditingSnapshot, CardEditingError>] = []
    var createLinkResults: [Result<Void, CardEditingError>] = []
    var deleteLinkResults: [Result<Void, CardEditingError>] = []
    var fetchLinksResults: [Result<[CardEditingLink], CardEditingError>] = []
    var replaceBackgroundResults: [Result<String, CardEditingError>] = []
    var removeBackgroundResults: [Result<Void, CardEditingError>] = []
    var inlineImageUploadResults: [Result<CardEditingInlineImageUpload, CardEditingError>] = []

    var createGate: AsyncGate?
    var updateGate: AsyncGate?
    var createLinkGate: AsyncGate?
    var replaceBackgroundGate: AsyncGate?

    private(set) var events: [Event] = []
    private(set) var createRequests: [CreateRequest] = []
    private(set) var updateRequests: [SaveRequest] = []
    private(set) var createLinkRequests: [CardEditingLink] = []
    private(set) var deleteLinkRequests: [CardEditingLink] = []
    private(set) var fetchLinksRequests: [String] = []
    private(set) var replaceBackgroundRequests: [CardEditingImage] = []
    private(set) var removeBackgroundRequests: [String] = []
    private(set) var inlineImageUploadRequests: [CardEditingImage] = []

    func create(
        draft: CardEditingDraft,
        createRequestID: String
    ) async throws -> CardEditingSnapshot {
        createRequests.append(
            .init(createRequestID: createRequestID, draft: draft)
        )
        events.append(.create(draft))
        let result = createResults.removeFirst()
        if let createGate, createRequests.count == 1 {
            await createGate.wait()
        }
        return try result.get()
    }

    func update(cardID: String, draft: CardEditingDraft) async throws -> CardEditingSnapshot {
        updateRequests.append(.init(cardID: cardID, draft: draft))
        events.append(.update(cardID: cardID, draft: draft))
        if let updateGate {
            await updateGate.wait()
        }
        return try updateResults.removeFirst().get()
    }

    func createLink(_ link: CardEditingLink) async throws {
        createLinkRequests.append(link)
        events.append(
            .createLink(
                sourceCardID: link.sourceCardID,
                targetCardID: link.targetCardID
            )
        )
        if let createLinkGate {
            await createLinkGate.wait()
        }
        try createLinkResults.removeFirst().get()
    }

    func deleteLink(_ link: CardEditingLink) async throws {
        deleteLinkRequests.append(link)
        events.append(
            .deleteLink(
                sourceCardID: link.sourceCardID,
                targetCardID: link.targetCardID
            )
        )
        try deleteLinkResults.removeFirst().get()
    }

    func fetchLinks(cardID: String) async throws -> [CardEditingLink] {
        fetchLinksRequests.append(cardID)
        return try fetchLinksResults.removeFirst().get()
    }

    func replaceBackground(
        cardID: String,
        image: CardEditingImage
    ) async throws -> String {
        replaceBackgroundRequests.append(image)
        events.append(.replaceBackground(cardID: cardID))
        if let replaceBackgroundGate {
            await replaceBackgroundGate.wait()
        }
        return try replaceBackgroundResults.removeFirst().get()
    }

    func removeBackground(cardID: String) async throws {
        removeBackgroundRequests.append(cardID)
        events.append(.removeBackground(cardID: cardID))
        try removeBackgroundResults.removeFirst().get()
    }

    func uploadInlineImage(
        _ image: CardEditingImage
    ) async throws -> CardEditingInlineImageUpload {
        inlineImageUploadRequests.append(image)
        return try inlineImageUploadResults.removeFirst().get()
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
