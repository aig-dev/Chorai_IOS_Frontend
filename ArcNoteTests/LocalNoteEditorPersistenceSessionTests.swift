import XCTest
import CoreFlow
import Combine
import SwiftUI
import WebKit
@testable import BlockNoteEditor
@testable import ArcNote

@MainActor
final class LocalNoteEditorPersistenceSessionTests: XCTestCase {
    private let alice = NoteStoreScope(actorID: "alice", environmentID: "local")
    private let bob = NoteStoreScope(actorID: "bob", environmentID: "local")
    private let carol = NoteStoreScope(actorID: "carol", environmentID: "local")

    func testBundledEditorSelectionAndRichEditPersistInReopenedNote() async throws {
        let id = UUID().uuidString
        let scope = NoteStoreScope(actorID: id, environmentID: "offline-editor-test")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let library = NoteLibraryStore(rootURL: root, service: { EditorOfflineTransport(scope: $0) })
        let reopened = NoteLibraryStore(rootURL: root, service: { EditorOfflineTransport(scope: $0) })
        addTeardownBlock { @MainActor in
            await library.configure(scope: nil, cloudEnabled: false)
            await reopened.configure(scope: nil, cloudEnabled: false)
            try FileManager.default.removeItem(at: root)
        }
        await library.configure(scope: scope, cloudEnabled: false)
        let service = LocalCoreCardEditingService(identifier: nil, creationID: id, scope: scope, library: library)
        let store = CardEditingStore(cardID: nil, createRequestID: id,
            draft: .init(title: nil, content: "", tags: [], isPublic: false),
            backgroundMediaRef: nil, links: [], service: service, preservesLocalDrafts: true)
        let model = BlockNoteCardEditorModel(document: .init(contentJSON: nil,
            fallbackMarkdown: "Plain paragraph\n\n## **Rich heading**")) { revision in
            _ = store.applyBodyRevision(content: revision.fallbackMarkdown,
                contentJSON: revision.contentJSON, revision: revision.revision)
        }
        let host = UIHostingController(rootView: BlockNoteCardEditor(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }

        func observe(_ description: String, _ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(10)
            while !predicate(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            _ = try XCTUnwrap(predicate() ? true : nil, description)
        }
        try await observe("Generated editor ready") { model.availability == .ready }
        func webView(in view: UIView) -> WKWebView? {
            if let result = view as? WKWebView { return result }
            for child in view.subviews {
                if let result = webView(in: child) { return result }
            }
            return nil
        }
        let web = try XCTUnwrap(webView(in: host.view))
        // Move only the DOM caret. The native model must learn both positions through the bridge.
        func selectText(_ text: String) async throws {
            let script = """
                const editor = document.querySelector('.bn-editor[contenteditable=true]');
                editor.focus();
                const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                  if (node.textContent === text) {
                    window.getSelection().setBaseAndExtent(node, 4, node, 4);
                    return true;
                  }
                }
                return false;
                """
            let matched = try await web.callAsyncJavaScript(script, arguments: ["text": text], in: nil, contentWorld: .page)
            XCTAssertEqual(matched as? Bool, true)
        }
        try await selectText("Plain paragraph")
        try await observe("Caret in plain paragraph") {
            model.selectionState?.blockType == .paragraph && model.selectionState?.formats.bold == false
        }
        try await selectText("Rich heading")
        try await observe("Caret moved to bold heading") {
            model.selectionState?.blockType == .heading2 && model.selectionState?.formats.bold == true
        }
        let before = model.revision
        let inserted = try await web.evaluateJavaScript("document.execCommand('insertText', false, ' saved')")
        XCTAssertEqual(inserted as? Bool, true)
        try await observe("Edited body accepted by native store") {
            model.revision > before && store.bodyRevision == model.revision
                && store.draft.content.contains("Rich saved heading")
        }
        let snapshot = try await model.requestSnapshot()
        XCTAssertEqual(snapshot.revision, store.bodyRevision)
        XCTAssertEqual(snapshot.contentJSON, store.draft.contentJSON)
        XCTAssertEqual(snapshot.fallbackMarkdown, store.draft.content)
        let saved = await store.save()
        XCTAssertTrue(saved)
        await library.configure(scope: nil, cloudEnabled: false)
        await reopened.configure(scope: scope, cloudEnabled: false)
        let note = try await reopened.open(identifier: "local-note:" + id, scope: scope)
        XCTAssertEqual(note.body.content, snapshot.fallbackMarkdown)
        XCTAssertEqual(note.body.contentJSON, snapshot.contentJSON)
        let json = try XCTUnwrap(note.body.contentJSON)
        let document = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let blocks = try XCTUnwrap((document as? [[String: Any]]) ?? (document as? [String: Any])?["blocks"] as? [[String: Any]])
        let heading = try XCTUnwrap(blocks.first { $0["type"] as? String == "heading" })
        XCTAssertEqual((heading["props"] as? [String: Any])?["level"] as? Int, 2)
        let spans = try XCTUnwrap(heading["content"] as? [[String: Any]])
        XCTAssertEqual(spans.compactMap { $0["text"] as? String }.joined(), "Rich saved heading")
        XCTAssertTrue(spans.allSatisfy { ($0["styles"] as? [String: Any])?["bold"] as? Bool == true })
    }

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
