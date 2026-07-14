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

    func testStageBackgroundBeforeCardIDOnlyChangesLocalPreview() {
        let service = MockCardEditingService()
        let store = makeNewStore(service: service)

        store.stageBackground(validImage)

        XCTAssertEqual(store.pendingBackground, validImage)
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
        XCTAssertEqual(store.pendingBackground, validImage)
        XCTAssertEqual(store.failureStage, .replacingBackground)

        let retrySucceeded = await store.retry()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(service.createRequests.count, 1)
        XCTAssertEqual(service.updateRequests.count, 0)
        XCTAssertEqual(service.replaceBackgroundRequests.count, 2)
        XCTAssertEqual(store.backgroundMediaRef, "med_1")
        XCTAssertNil(store.pendingBackground)
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
        XCTAssertNil(store.pendingBackground)
        XCTAssertFalse(store.isDirty)
    }

    func testRemoveBackgroundFromUnsavedCardClearsOnlyStagedPreview() async {
        let service = MockCardEditingService()
        let store = makeNewStore(service: service)
        store.stageBackground(validImage)

        let removed = await store.removeBackground()
        XCTAssertTrue(removed)

        XCTAssertNil(store.pendingBackground)
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertTrue(service.removeBackgroundRequests.isEmpty)
        XCTAssertTrue(service.events.isEmpty)
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
        XCTAssertEqual(store.pendingBackground, validImage)
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

        _ = await store.save()

        XCTAssertEqual(service.updateRequests.count, 2)
        XCTAssertEqual(service.updateRequests[0], service.updateRequests[1])
        XCTAssertEqual(store.draft.contentJSON, json)
        XCTAssertEqual(store.draft.editorAtmosphere, "rain")
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

    func testRemoveBackgroundFailureKeepsCommittedRefUntilRetrySucceeds() async {
        let service = MockCardEditingService()
        service.removeBackgroundResults = [
            .failure(.transport(code: "remove_failed")),
            .success(())
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )

        _ = await store.removeBackground()
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")

        _ = await store.retry()
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(service.removeBackgroundRequests, ["ast_1", "ast_1"])
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

    var createResults: [Result<CardEditingSnapshot, CardEditingError>] = []
    var updateResults: [Result<CardEditingSnapshot, CardEditingError>] = []
    var createLinkResults: [Result<Void, CardEditingError>] = []
    var deleteLinkResults: [Result<Void, CardEditingError>] = []
    var replaceBackgroundResults: [Result<String, CardEditingError>] = []
    var removeBackgroundResults: [Result<Void, CardEditingError>] = []

    var createGate: AsyncGate?
    var updateGate: AsyncGate?
    var createLinkGate: AsyncGate?
    var replaceBackgroundGate: AsyncGate?

    private(set) var events: [Event] = []
    private(set) var createRequests: [CardEditingDraft] = []
    private(set) var updateRequests: [SaveRequest] = []
    private(set) var createLinkRequests: [CardEditingLink] = []
    private(set) var deleteLinkRequests: [CardEditingLink] = []
    private(set) var replaceBackgroundRequests: [CardEditingImage] = []
    private(set) var removeBackgroundRequests: [String] = []

    func create(draft: CardEditingDraft) async throws -> CardEditingSnapshot {
        createRequests.append(draft)
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
