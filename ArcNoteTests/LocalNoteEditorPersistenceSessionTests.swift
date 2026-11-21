import XCTest
import CoreFlow
import Combine
@testable import BlockNoteEditor
@testable import ArcNote

@MainActor
final class LocalNoteEditorPersistenceSessionTests: XCTestCase {
    private let alice = NoteStoreScope(actorID: "alice", environmentID: "local")
    private let bob = NoteStoreScope(actorID: "bob", environmentID: "local")
    private let carol = NoteStoreScope(actorID: "carol", environmentID: "local")

    func testDisappearBeforeAppliedEventSavesFinalRevision() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        let gate = EditorExecutionGate()
        let entered = expectation(description: "draining")
        fixture.model.controller.attach(drainAcceptedEvents: {
            entered.fulfill()
            await gate.wait()
            fixture.edit("Final", revision: 1)
        }, commandHandler: { _ in })
        fixture.persistence.setVisible(false)
        let flush = Task { await fixture.persistence.flushAcceptedEdits() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertTrue(fixture.library.notes.isEmpty)
        gate.open()
        let flushed = await flush.value
        XCTAssertTrue(flushed)
        XCTAssertEqual(fixture.library.notes.first?.body.content, "Final")
        XCTAssertEqual(fixture.library.scope, alice)
    }

    func testDismantleAfterDisappearOwnsFinalSaveWithoutViewTask() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        let saved = expectation(description: "saved after closing")
        fixture.service.onSave = { saved.fulfill() }
        fixture.model.controller.attach(drainAcceptedEvents: {
            fixture.edit("Last accepted body", revision: 1)
        }, commandHandler: { _ in })
        fixture.persistence.setVisible(false)
        fixture.model.controller.detach()
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(fixture.library.notes.first?.body.content, "Last accepted body")
        XCTAssertFalse(fixture.store.isDirty)
    }

    func testInactiveDrainDoesNotSealAndCanSaveNextInput() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        fixture.model.controller.attach { _ in }
        fixture.edit("One", revision: 1)
        let first = await fixture.persistence.flushAcceptedEdits()
        XCTAssertTrue(first)
        XCTAssertEqual(fixture.model.controller.attachment?.isClosing, false)
        fixture.edit("Two", revision: 2)
        let second = await fixture.persistence.flushAcceptedEdits()
        XCTAssertTrue(second)
        XCTAssertEqual(fixture.library.notes.first?.body.content, "Two")
    }

    func testScopeChangeWaitsForOriginalScopeSaveAndUsesLatestTarget() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        var target: NoteStoreScope? = bob
        let controller = LocalNotesController(library: fixture.library, access: { (target, false) })
        controller.registerEditor(fixture.persistence)
        fixture.model.controller.attach { _ in }
        fixture.edit("Private A", revision: 1)
        let started = expectation(description: "saving original")
        let gate = EditorExecutionGate()
        fixture.service.beforeSave = { started.fulfill(); await gate.wait() }
        let transition = controller.refreshAccess()
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(fixture.library.scope, alice)
        XCTAssertEqual(controller.scopeTransition, .flushing)
        XCTAssertFalse(controller.canDisplayNotes(for: bob))
        target = carol
        gate.open()
        await transition.value
        XCTAssertEqual(fixture.library.scope, carol)
        XCTAssertEqual(controller.scopeTransition, .ready)
        await fixture.library.configure(scope: alice, cloudEnabled: false)
        XCTAssertEqual(fixture.library.notes.first?.body.content, "Private A")
    }

    func testSaveFailureRetainsSessionAndRetryUsesLatestTarget() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        var target: NoteStoreScope? = bob
        let controller = LocalNotesController(library: fixture.library, access: { (target, false) })
        controller.registerEditor(fixture.persistence)
        fixture.model.controller.attach { _ in }
        fixture.edit("Retained draft", revision: 1)
        fixture.service.shouldFail = true
        await controller.refreshAccess().value
        XCTAssertEqual(controller.scopeTransition, .failed)
        XCTAssertEqual(fixture.library.scope, alice)
        XCTAssertTrue(fixture.store.isDirty)
        XCTAssertNotNil(controller.editors[fixture.persistence.id])
        XCTAssertFalse(controller.canDisplayNotes(for: bob))
        target = carol
        fixture.service.shouldFail = false
        await controller.retryScopeTransition().value
        XCTAssertEqual(controller.scopeTransition, .ready)
        XCTAssertEqual(fixture.library.scope, carol)
        XCTAssertNil(controller.editors[fixture.persistence.id])
        await fixture.library.configure(scope: alice, cloudEnabled: false)
        XCTAssertEqual(fixture.library.notes.first?.body.content, "Retained draft")
    }

    func testOldBindingCompletionCannotUnregisterReplacement() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        let controller = LocalNotesController(library: fixture.library, access: { (self.alice, false) })
        controller.registerEditor(fixture.persistence)
        let gate = EditorExecutionGate()
        let entered = expectation(description: "old drain")
        let saved = expectation(description: "saved")
        fixture.service.onSave = { saved.fulfill() }
        fixture.model.controller.attach(drainAcceptedEvents: {
            entered.fulfill(); await gate.wait(); fixture.edit("Old accepted", revision: 1)
        }, commandHandler: { _ in })
        fixture.persistence.setVisible(false)
        fixture.model.controller.beginClosing()
        await fulfillment(of: [entered], timeout: 3)
        fixture.model.controller.attach { _ in }
        gate.open()
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertNotNil(controller.editors[fixture.persistence.id])
        XCTAssertEqual(fixture.model.controller.attachment?.isClosing, false)
    }

    func testSnapshotCannotCompleteIntoReplacementEditor() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        let sent = expectation(description: "snapshot sent")
        var requestID: String?
        let original = fixture.model.controller
        original.attach { command in requestID = command.snapshotRequestID; if requestID != nil { sent.fulfill() } }
        fixture.model.receive(.availabilityChanged(.ready))
        let snapshot = Task { try await fixture.model.requestSnapshot() }
        await fulfillment(of: [sent], timeout: 3)
        original.complete(snapshot: .init(requestID: try XCTUnwrap(requestID), revision: 1, contentJSON: "[]", fallbackMarkdown: "Old"))
        fixture.model.receive(.bridgeError(code: "injected"))
        fixture.model.retryAfterBridgeFailure()
        do { _ = try await snapshot.value; XCTFail("Old snapshot accepted by replacement") }
        catch CardEditorBodyError.unavailable {} catch { XCTFail("\(error)") }
    }

    func testScopeMismatchHidesOldNotesBeforeRefreshStarts() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        defer { fixture.removeFiles() }
        let controller = LocalNotesController(library: fixture.library, access: { (self.bob, false) })
        XCTAssertEqual(controller.scopeTransition, .ready)
        XCTAssertFalse(controller.canDisplayNotes(for: bob))
    }
}

@MainActor
final class EditorExecutionGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if opened { return }; await withCheckedContinuation { waiters.append($0) } }
    func open() { opened = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}

@MainActor
private final class NoteEditorFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let library: NoteLibraryStore
    let service: NoteEditorTestService
    let store: CardEditingStore
    let model: BlockNoteCardEditorModel
    let persistence: LocalNoteEditorPersistenceSession
    init(scope: NoteStoreScope) async throws {
        library = NoteLibraryStore(rootURL: root, service: { EditorOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        service = NoteEditorTestService(library: library, scope: scope)
        store = CardEditingStore(cardID: nil, createRequestID: "draft", draft: .init(title: nil, content: "", tags: [], isPublic: false), backgroundMediaRef: nil, links: [], service: service, preservesLocalDrafts: true)
        let store = self.store
        model = BlockNoteCardEditorModel(document: .init(contentJSON: nil, fallbackMarkdown: ""), onDocumentChanged: {
            _ = store.applyBodyRevision(content: $0.fallbackMarkdown, contentJSON: $0.contentJSON, revision: $0.revision)
        })
        persistence = LocalNoteEditorPersistenceSession(scope: scope, editingStore: store, bodyModel: model, isNew: true, initialIsPublic: false)
    }
    func edit(_ body: String, revision: Int) {
        let data = try! JSONSerialization.data(withJSONObject: [["id": "body", "type": "paragraph", "content": [["type": "text", "text": body]]]])
        model.receive(.documentChanged(.init(revision: revision, contentJSON: String(decoding: data, as: UTF8.self), fallbackMarkdown: body)))
    }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class NoteEditorTestService: CoreCardEditingServing {
    let library: NoteLibraryStore
    let scope: NoteStoreScope
    var shouldFail = false
    var beforeSave: (() async -> Void)?
    var onSave: (() -> Void)?
    init(library: NoteLibraryStore, scope: NoteStoreScope) { self.library = library; self.scope = scope }
    private func persist(_ draft: CardEditingDraft, id: String?) async throws -> CardEditingSnapshot {
        await beforeSave?()
        if shouldFail { throw CardEditingError.transport(code: "injected_disk_failure") }
        let note = try await library.save(identifier: id, createID: "draft", body: OfflineNoteBody(draft: draft), scope: scope)
        onSave?()
        return .init(id: NoteLibraryStore.identifier(note), title: draft.title, content: draft.content, contentJSON: draft.contentJSON, tags: draft.tags, isPublic: draft.isPublic, backgroundMediaRef: nil)
    }
    func create(draft: CardEditingDraft, createRequestID: String) async throws -> CardEditingSnapshot { try await persist(draft, id: nil) }
    func update(cardID: String, draft: CardEditingDraft) async throws -> CardEditingSnapshot { try await persist(draft, id: cardID) }
    func createLink(_ link: CardEditingLink) async throws -> CardEditingLink { throw CardEditingError.transport(code: "unused") }
    func deleteLink(_ link: CardEditingLink) async throws { throw CardEditingError.transport(code: "unused") }
    func fetchLinks(cardID: String) async throws -> [CardEditingLink] { [] }
    func uploadInlineImage(_ image: CardEditingImage) async throws -> CardEditingInlineImageUpload { throw CardEditingError.transport(code: "unused") }
    func replaceBackground(cardID: String, image: CardEditingImage) async throws -> String { throw CardEditingError.transport(code: "unused") }
    func removeBackground(cardID: String) async throws { throw CardEditingError.transport(code: "unused") }
}
private struct EditorOfflineTransport: NoteSyncServing {
    let scope: NoteStoreScope
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.notReady }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot { throw NoteSyncFailure.notReady }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.notReady }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}
