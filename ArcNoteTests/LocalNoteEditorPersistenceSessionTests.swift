import XCTest
@testable import CoreFlow
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

    func testFinalBodyFlushLeavesStagedBackgroundForExplicitSave() async throws {
        let fixture = try await NoteEditorFixture(scope: alice)
        addTeardownBlock { @MainActor in
            await fixture.library.configure(scope: nil, cloudEnabled: false)
            fixture.removeFiles()
        }
        fixture.edit("Body before selection", revision: 1)
        let image = CardEditingImage(data: Data([1]), filename: "chosen.png", mimeType: "image/png")
        XCTAssertTrue(fixture.store.stageBackground(image))
        let flushed = await fixture.persistence.closeForScopeChange()
        XCTAssertTrue(flushed)
        XCTAssertNil(fixture.store.failureStage)
        XCTAssertEqual(fixture.store.pendingBackground, image)
        XCTAssertEqual(fixture.library.notes.first?.body.content, "Body before selection")
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
    var afterLocalSave: (() async -> Void)?
    var onSave: (() -> Void)?
    init(library: NoteLibraryStore, scope: NoteStoreScope) { self.library = library; self.scope = scope }
    private func persist(_ draft: CardEditingDraft, id: String?) async throws -> CardEditingSnapshot {
        await beforeSave?()
        if shouldFail { throw CardEditingError.transport(code: "injected_disk_failure") }
        let note = try await library.save(identifier: id, createID: "draft", body: OfflineNoteBody(draft: draft), scope: scope)
        await afterLocalSave?()
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

@MainActor
final class LocalNoteBackgroundRecoveryTests: XCTestCase {
    private let png = CardEditingImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!,
        filename: "picker.png", mimeType: "image/png")

    private func setupEditor(auth: AuthManager? = nil) async throws -> BackgroundEditorFixture {
        let fixture = BackgroundEditorFixture(auth: auth)
        addTeardownBlock { @MainActor in
            await fixture.library.configure(scope: nil, cloudEnabled: false)
            try FileManager.default.removeItem(at: fixture.root)
        }
        await fixture.library.configure(scope: fixture.scope, cloudEnabled: true)
        return fixture
    }

    func testBlankReopenedPlaceholderCannotCreateAfterCancelOrUnreadableCommand() async throws {
        for damaged in [false, true] {
            let owner = BackgroundRecoveryFixtureOwner()
            addTeardownBlock { @MainActor in
                await owner.library.configure(scope: nil, cloudEnabled: false)
                try FileManager.default.removeItem(at: owner.root)
            }
            try await owner.prepare(held: false)
            let service = owner.editor(new: false)
            _ = try await service.openExisting()
            let target = try await owner.library.backgroundTarget(identifier: owner.identifier, createID: owner.id, scope: owner.scope)
            if damaged {
                let directory = target.store.directoryURL.appendingPathComponent("background-commands")
                let slot = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
                try Data("malformed".utf8).write(to: slot)
                do { _ = try await service.readBackground(); XCTFail("Damaged original was accepted") }
                catch NoteBackgroundError.unreadable {}
            } else {
                _ = try await service.readBackground()
                try await service.cancelBackground()
            }
            let editing = CardEditingStore(cardID: owner.identifier, draft: .init(title: nil, content: "", tags: [], isPublic: false),
                backgroundMediaRef: nil, links: [], service: service, preservesLocalDrafts: true)
            let model = BlockNoteCardEditorModel(document: .init(contentJSON: nil, fallbackMarkdown: ""))
            let session = LocalNoteEditorPersistenceSession(scope: owner.scope, editingStore: editing, bodyModel: model,
                isNew: false, initialIsPublic: false, isUnpublishedEmptyPlaceholder: { service.isUnpublishedEmptyPlaceholder })
            let blank = #"[{"type":"paragraph","content":[],"children":[]},{"type":"paragraph","content":[],"children":[]}]"#
            _ = editing.applyBodyRevision(content: "\n", contentJSON: blank, revision: 2)
            XCTAssertTrue(session.isUntouchedNewDraft)
            do {
                _ = try await session.saveBodyAndChosenBackground(service: service, admission: service.backgroundAdmission(), backgroundLoaded: !damaged) {}
                XCTFail("Explicit blank Save persisted the first body")
            } catch { XCTAssertEqual(error as? NoteBackgroundError, .needsBody) }
            await owner.library.synchronize(forceRetry: true)
            let placeholder = try await target.store.note(localID: owner.id)
            XCTAssertEqual(placeholder?.bodyRevision, 1)
            XCTAssertEqual(placeholder?.acknowledgedBodyRevision, 0)
            XCTAssertNil(placeholder?.serverAssetID)
            let before = await owner.counts()
            XCTAssertEqual(before, "creates=0 uploads=0 writes=0")
            _ = editing.applyBodyRevision(content: "Known first body", contentJSON: nil, revision: 3)
            do {
                _ = try await session.saveBodyAndChosenBackground(service: service, admission: service.backgroundAdmission(), backgroundLoaded: !damaged) {}
            } catch { XCTAssertTrue(damaged); XCTAssertEqual(error as? NoteBackgroundError, .unreadable) }
            await owner.library.synchronize(forceRetry: true)
            let saved = try await target.store.note(localID: owner.id)
            XCTAssertEqual(saved?.body.content, "Known first body")
            XCTAssertEqual(saved?.acknowledgedBodyRevision, saved?.bodyRevision)
            XCTAssertEqual(saved?.serverAssetID, "fixture-asset")
            XCTAssertEqual(saved?.isPublic, false)
            let after = await owner.counts()
            XCTAssertEqual(after, "creates=1 uploads=0 writes=0")
        }
    }

    func testLostUploadPatchAndRemovalReopenAndReuseOriginalDecision() async throws {
        for loss in [BackgroundTestWire.Loss.upload, .patch, .remove] {
            let f = try await setupEditor()
            f.wire.current = .init(revision: 4, displayRef: loss == .remove ? "old-background" : nil)
            let original = try await f.openEditor()
            try await original.observeBackgroundChoice()
            _ = try await original.stageBackground(loss == .remove ? nil : png)
            let staged = try XCTUnwrap(original.pendingBackground)
            f.wire.loss = loss
            do { _ = try await original.submitBackground(original.backgroundAdmission()); XCTFail("Lost response was confirmed") }
            catch NoteBackgroundError.unknown {}
            await f.library.configure(scope: nil, cloudEnabled: false)
            await f.library.configure(scope: f.scope, cloudEnabled: true)
            let reopened = try await f.openEditor()
            XCTAssertEqual(reopened.pendingBackground?.id, staged.id)
            XCTAssertFalse(reopened.pendingBackground?.canCancel ?? true)
            if loss == .patch { XCTAssertEqual(reopened.pendingBackground?.logicalRef, f.wire.ref) }
            let current = try await reopened.submitBackground(reopened.backgroundAdmission())
            XCTAssertEqual(current, f.wire.current.displayRef)
            XCTAssertNil(reopened.pendingBackground)
            XCTAssertEqual(f.wire.current.revision, 5)
            XCTAssertEqual(Set(f.wire.uploads.map(\.id)).union(f.wire.writes.map(\.id)), [staged.id])
            XCTAssertEqual(Set(f.wire.writes.map(\.baseline)), [4])
            XCTAssertTrue(f.wire.bytes.allSatisfy { $0 == png.data })
            XCTAssertEqual(f.wire.uploads.count, loss == .remove ? 0 : loss == .upload ? 2 : 1)
            XCTAssertEqual(f.wire.writes.count, loss == .upload ? 1 : 2)
            XCTAssertEqual(f.library.notes.first?.isPublic, true)
            XCTAssertEqual(f.library.notes.first?.body.content, "Original body")
        }
    }

    func testStaleABARefreshRequiresNewChoiceAndFailedRefreshKeepsOriginal() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        let original = try XCTUnwrap(editor.pendingBackground)
        f.wire.current = .init(revision: 2, displayRef: nil)
        f.wire.failRead = true
        do { _ = try await editor.submitBackground(editor.backgroundAdmission()); XCTFail("Stale accepted") }
        catch NoteBackgroundError.unknown {}
        XCTAssertEqual(editor.pendingBackground?.id, original.id)
        f.wire.failRead = false
        do { _ = try await editor.submitBackground(editor.backgroundAdmission()); XCTFail("Stale accepted") }
        catch NoteBackgroundError.stale {}
        XCTAssertNil(editor.pendingBackground)
        XCTAssertEqual(f.wire.current.revision, 2)
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        XCTAssertNotEqual(editor.pendingBackground?.id, original.id)
        XCTAssertEqual(editor.pendingBackground?.baseline, 2)
        _ = try await editor.submitBackground(editor.backgroundAdmission())
        XCTAssertEqual(f.wire.current.revision, 3)
    }

    func testInitialRejectionCanCancelButExpiredUploadRetainsOriginalAfterRef() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        f.wire.uploadError = .rejected
        do { _ = try await editor.submitBackground(editor.backgroundAdmission()); XCTFail("Accepted rejected upload") }
        catch NoteBackgroundError.rejected {}
        XCTAssertEqual(editor.pendingBackground?.phase, .rejected)
        try await editor.cancelBackground()
        XCTAssertNil(editor.pendingBackground)
        f.wire.uploadError = nil
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        f.wire.writeError = .expired
        do { _ = try await editor.submitBackground(editor.backgroundAdmission()); XCTFail("Expired ref acknowledged") }
        catch NoteBackgroundError.expired {}
        let frozen = try XCTUnwrap(editor.pendingBackground)
        XCTAssertEqual(frozen.phase, .refreshUpload)
        XCTAssertEqual(frozen.logicalRef, f.wire.ref)
        f.wire.uploadError = .unknown
        let reopened = try await f.openEditor()
        do { _ = try await reopened.submitBackground(reopened.backgroundAdmission()); XCTFail("Malformed refresh acknowledged") }
        catch NoteBackgroundError.unknown {}
        XCTAssertEqual(reopened.pendingBackground, frozen)
        do { try await reopened.cancelBackground(); XCTFail("Canceled after original ref") }
        catch NoteBackgroundError.unresolved {}
        XCTAssertEqual(f.wire.uploads.last?.id, frozen.id)
        XCTAssertEqual(f.wire.bytes.last, png.data)
        f.wire.writeError = nil; f.wire.uploadError = nil
        _ = try await reopened.submitBackground(reopened.backgroundAdmission())
        XCTAssertNil(reopened.pendingBackground)
    }

    func testTrailingImageBytesCannotReplaceOriginalOrStartTransport() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        let original = try XCTUnwrap(editor.pendingBackground)
        // The exact jpeg2x3, frozenGIF and webPVP8 positives from Go's frozen image contract.
        let positives = [
            "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z",
            "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==",
            "UklGRj4AAABXRUJQVlA4IDIAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==",
        ]
        for positive in positives {
            var bytes = try XCTUnwrap(Data(base64Encoded: positive))
            bytes.append(0)
            try await editor.observeBackgroundChoice()
            let observationReads = f.wire.reads
            do {
                _ = try await editor.stageBackground(.init(data: bytes, filename: "picker", mimeType: "image/fixture"))
                XCTFail("Accepted trailing data")
            } catch NoteBackgroundError.invalidImage {}
            XCTAssertEqual(f.wire.reads, observationReads)
            XCTAssertTrue(f.wire.uploads.isEmpty)
            XCTAssertTrue(f.wire.writes.isEmpty)
            let reopened = try await f.openEditor()
            XCTAssertEqual(reopened.pendingBackground, original)
        }
    }

    func testWrongTargetAndChangedBytesCannotDispatchPendingBackground() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        let frozen = try XCTUnwrap(editor.pendingBackground)
        do {
            _ = try await editor.replaceBackground(cardID: "local-note:other", image: png)
            XCTFail("Dispatched another note's pending choice")
        } catch NoteBackgroundError.unresolved {}
        let files = try XCTUnwrap(FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        let path = try XCTUnwrap(files.first { $0.lastPathComponent == frozen.image?.relativePath })
        try Data("damaged".utf8).write(to: path)
        do { _ = try await editor.submitBackground(editor.backgroundAdmission()); XCTFail("Sent unverified bytes") }
        catch NoteLocalStoreError.attachmentMismatch {}
        XCTAssertTrue(f.wire.uploads.isEmpty)
        XCTAssertTrue(f.wire.writes.isEmpty)
        XCTAssertEqual(editor.pendingBackground?.id, frozen.id)
        do { _ = try await editor.readBackground(); XCTFail("Reported damaged bytes as settled") }
        catch NoteLocalStoreError.attachmentMismatch {}
        XCTAssertTrue(editor.backgroundUnreadable)
    }

    func testSaveCannotAdoptSameScopeSuccessorDuringBodyWrite() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        try await assertBodyWaitRetainsOriginal(f, editor: editor) { f.session += 1 }
    }

    func testExplicitRetryCannotPatchAfterSameLoginAccessRevocationDuringBodyWrite() async throws {
        prepareLinkAuth()
        let auth = AuthManager.shared
        let allowed = try XCTUnwrap(auth.accessState)
        let f = try await setupEditor(auth: auth)
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        f.wire.loss = .patch
        do { _ = try await editor.submitBackground(editor.backgroundAdmission()); XCTFail("Lost PATCH confirmed") }
        catch NoteBackgroundError.unknown {}
        let retry = try await f.openEditor()
        let command = try XCTUnwrap(retry.pendingBackground)
        XCTAssertEqual(command.phase, .attachedRef)
        XCTAssertNotNil(command.requiredBodyRevision)
        try await assertBodyWaitRetainsOriginal(f, editor: retry) {
            auth.applyAccess(AccessState(mode: "private_beta", status: "required", scope: nil, reasonCode: "account_restricted"))
            auth.applyAccess(allowed)
        }
        let restored = try await f.openEditor()
        XCTAssertEqual(restored.pendingBackground, command)
        _ = try await restored.submitBackground(restored.backgroundAdmission())
        XCTAssertEqual(f.wire.uploads.count, 1)
        XCTAssertEqual(f.wire.writes.map(\.id), [command.id, command.id])
        XCTAssertNil(restored.pendingBackground)
    }

    private func assertBodyWaitRetainsOriginal(_ f: BackgroundEditorFixture, editor: LocalCoreCardEditingService,
                                              changeAccess: () -> Void) async throws {
        let original = try XCTUnwrap(editor.pendingBackground)
        let uploads = f.wire.uploads.count
        let writes = f.wire.writes.count
        let body = NoteEditorTestService(library: f.library, scope: f.scope)
        body.afterLocalSave = { await f.library.synchronize(forceRetry: true) }
        let editing = CardEditingStore(cardID: "asset", draft: .init(title: nil, content: "Original body", tags: [], isPublic: true),
                                      backgroundMediaRef: nil, links: [], service: body, preservesLocalDrafts: true)
        _ = editing.applyBodyRevision(content: "Accepted during first session", contentJSON: nil, revision: 8)
        let model = BlockNoteCardEditorModel(document: .init(contentJSON: nil, fallbackMarkdown: "Original body"))
        let session = LocalNoteEditorPersistenceSession(scope: f.scope, editingStore: editing, bodyModel: model, isNew: false, initialIsPublic: true)
        let gate = EditorExecutionGate()
        let entered = expectation(description: "original Save is waiting for the independent body write")
        body.beforeSave = { entered.fulfill(); await gate.wait() }
        let admission = editor.backgroundAdmission()
        let save = Task { try await session.saveBodyAndChosenBackground(service: editor, admission: admission, backgroundLoaded: true) {} }
        await fulfillment(of: [entered], timeout: 5)
        defer { gate.open() }
        XCTAssertEqual(editor.pendingBackground?.phase, original.phase == .staged ? .submitted : original.phase)
        changeAccess()
        gate.open()
        do { _ = try await save.value; XCTFail("Old Save adopted the successor session") }
        catch NoteBackgroundError.unknown {} // The view reports this presentation as unconfirmed.
        catch NoteLocalStoreError.invalidScope {}
        XCTAssertEqual(editor.pendingBackground?.id, original.id)
        XCTAssertEqual(f.wire.uploads.count, uploads)
        XCTAssertEqual(f.wire.writes.count, writes)
        let reopened = try await f.library.open(identifier: "asset", scope: f.scope)
        XCTAssertEqual(reopened.body.content, "Accepted during first session")
    }

    func testFailureBeforeFreezeReportsOnlyAcknowledgedBodyRevision() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        let other = try await f.openEditor()
        try await other.cancelBackground() // The first editor still holds the old command in memory.
        let editing = CardEditingStore(cardID: "asset", draft: .init(title: nil, content: "Original body", tags: [], isPublic: true),
                                      backgroundMediaRef: nil, links: [], service: editor, preservesLocalDrafts: true)
        _ = editing.applyBodyRevision(content: "Still waiting locally", contentJSON: nil, revision: 9)
        let model = BlockNoteCardEditorModel(document: .init(contentJSON: nil, fallbackMarkdown: "Original body"))
        let session = LocalNoteEditorPersistenceSession(scope: f.scope, editingStore: editing, bodyModel: model, isNew: false, initialIsPublic: true)
        do {
            _ = try await session.saveBodyAndChosenBackground(service: editor, admission: editor.backgroundAdmission(), backgroundLoaded: true) {}
            XCTFail("Stale slot froze over a newer choice")
        } catch let reason as NoteBackgroundError {
            XCTAssertEqual(reason, .changed)
            XCTAssertFalse(session.backgroundFailureMessage(reason, bodyRevision: 9).contains("Body saved"))
        }
        let beforeFlush = try await f.library.open(identifier: "asset", scope: f.scope)
        XCTAssertEqual(beforeFlush.body.content, "Original body")
        let flushed = await session.flushAcceptedEdits()
        XCTAssertTrue(flushed)
        let afterFlush = try await f.library.open(identifier: "asset", scope: f.scope)
        XCTAssertEqual(afterFlush.body.content, "Still waiting locally")
        XCTAssertTrue(session.backgroundFailureMessage(.changed, bodyRevision: 9).contains("Body saved"))
        XCTAssertTrue(f.wire.uploads.isEmpty)
        // Existing notes still accept a deliberately blank document.
        _ = editing.applyBodyRevision(content: "", contentJSON: #"[{"type":"paragraph","content":[],"children":[]}]"#, revision: 10)
        let savedEmpty = await session.flushAcceptedEdits()
        XCTAssertTrue(savedEmpty)
        let emptied = try await f.library.open(identifier: "asset", scope: f.scope)
        XCTAssertEqual(emptied.body.content, "")
        XCTAssertEqual(emptied.serverAssetID, beforeFlush.serverAssetID)
    }

    func testQueuedOriginalReceiptAndRetirementCannotMutateAfterSameScopeGenerationChanges() async throws {
        for holdWrite in [false, true] {
            let f = try await setupEditor()
            try await assertQueuedReceiptRetainsOriginal(f, holdWrite: holdWrite) { f.session += 1 }
        }
    }

    func testProductAccessRevocationFencesQueuedBackgroundReceipt() async throws {
        prepareLinkAuth()
        let auth = AuthManager.shared
        let session = auth.sessionGeneration
        let allowed = try XCTUnwrap(auth.accessState)
        let required = AccessState(mode: "private_beta", status: "required", scope: nil, reasonCode: "account_restricted")
        XCTAssertTrue(required.isValid)
        for holdWrite in [false, true] {
            let f = try await setupEditor(auth: auth)
            try await assertQueuedReceiptRetainsOriginal(f, holdWrite: holdWrite) {
                auth.applyAccess(required)
                XCTAssertFalse(auth.canOpenLocalNotes)
                XCTAssertFalse(auth.canEnterProduct)
                // Readmit the same login before its already queued SQLite effect runs.
                auth.applyAccess(allowed)
                XCTAssertTrue(auth.canEnterProduct)
                XCTAssertEqual(auth.sessionGeneration, session)
            }
            f.wire.onUpload = nil
            f.wire.onWrite = nil
            let reopened = try await f.openEditor()
            let pending = try XCTUnwrap(reopened.pendingBackground)
            let confirmed = try await reopened.submitBackground(reopened.backgroundAdmission())
            XCTAssertNotNil(confirmed)
            XCTAssertNil(reopened.pendingBackground)
            XCTAssertEqual(f.wire.writes.last?.id, pending.id)
        }
    }

    func testTemporarilyUnavailableAccessRetainsLocalChoiceWithoutNetwork() async throws {
        prepareLinkAuth()
        let auth = AuthManager.shared
        let allowed = try XCTUnwrap(auth.accessState)
        let f = try await setupEditor(auth: auth)
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        let admission = editor.backgroundAdmission()
        auth.applyAccess(AccessState(mode: "unavailable", status: "required", scope: nil, reasonCode: nil))
        XCTAssertTrue(auth.canOpenLocalNotes)
        XCTAssertFalse(auth.canEnterProduct)
        _ = try await editor.stageBackground(png)
        let original = try XCTUnwrap(editor.pendingBackground)
        do { _ = try await editor.submitBackground(admission); XCTFail("Sent while product unavailable") }
        catch NoteLocalStoreError.invalidScope {}
        XCTAssertTrue(f.wire.uploads.isEmpty)
        XCTAssertTrue(f.wire.writes.isEmpty)
        auth.applyAccess(allowed)
        let reopened = try await f.openEditor()
        XCTAssertEqual(reopened.pendingBackground?.id, original.id)
        _ = try await reopened.submitBackground(reopened.backgroundAdmission())
        XCTAssertEqual(f.wire.writes.map(\.id), [original.id])
    }

    private func assertQueuedReceiptRetainsOriginal(_ f: BackgroundEditorFixture, holdWrite: Bool,
                                                   changeAccess: () -> Void) async throws {
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        let original = try XCTUnwrap(editor.pendingBackground)
        let target = try await f.library.backgroundTarget(identifier: "asset", createID: "unused", scope: f.scope)
        let queued = expectation(description: "real private Core Data queue blocked before the next receipt effect")
        let checked = expectation(description: "old session authorized the returned transport response")
        let release = DispatchSemaphore(value: 0)
        var blocker: Task<Void, Error>?
        let beforeReply: () async -> Void = {
            blocker = Task {
                try await target.store.transaction { _ in
                    queued.fulfill()
                    guard release.wait(timeout: .now() + 10) == .success else { throw NoteBackgroundError.unknown }
                }
            }
            await self.fulfillment(of: [queued], timeout: 4)
            f.nextAccessCheck = { checked.fulfill() }
        }
        if holdWrite { f.wire.onWrite = beforeReply } else { f.wire.onUpload = beforeReply }
        let delivery = Task { try await editor.submitBackground(editor.backgroundAdmission()) }
        await fulfillment(of: [checked], timeout: 5)
        changeAccess()
        release.signal()
        try await blocker?.value
        do { _ = try await delivery.value; XCTFail("A queued old-session effect was accepted") }
        catch NoteLocalStoreError.invalidScope {}
        let after = try await target.store.background(localID: original.localID)
        XCTAssertEqual(after?.id, original.id)
        XCTAssertEqual(after?.phase, holdWrite ? .attachedRef : .submitted)
        XCTAssertEqual(after?.logicalRef, holdWrite ? f.wire.ref : nil)
        let row = try await target.store.note(localID: original.localID)
        XCTAssertNil(row?.backgroundMediaRef)
        XCTAssertEqual(f.wire.writes.count, holdWrite ? 1 : 0)
    }

    func testSecondEditorReconcilesAttachedPhaseAndTerminalOriginal() async throws {
        let f = try await setupEditor()
        let first = try await f.openEditor()
        try await first.observeBackgroundChoice()
        _ = try await first.stageBackground(png)
        let original = try XCTUnwrap(first.pendingBackground)
        let upload = EditorExecutionGate(), patch = EditorExecutionGate()
        let uploading = expectation(description: "original upload entered")
        f.wire.onUpload = { uploading.fulfill(); await upload.wait() }
        f.wire.onWrite = { await patch.wait() }
        defer { upload.open(); patch.open() }
        let delivery = Task { try await first.submitBackground(first.backgroundAdmission()) }
        await fulfillment(of: [uploading], timeout: 5)
        let second = try await f.openEditor()
        let submitted = expectation(description: "second editor shows submitted")
        let attached = expectation(description: "second editor shows original attachedRef while PATCH is held")
        let settled = expectation(description: "second editor shows confirmed metadata and no Retry")
        var seen = Set<String>()
        let observer = Task {
            await second.observeStoredBackground { result in
                guard case .success = result else { return XCTFail("Failed to reconcile pending background") }
                if let command = second.pendingBackground, command.id == original.id,
                   seen.insert(command.phase.rawValue).inserted {
                    if command.phase == .submitted { submitted.fulfill() }
                    if command.phase == .attachedRef {
                        XCTAssertEqual(command.logicalRef, f.wire.ref)
                        attached.fulfill()
                    }
                } else if second.pendingBackground == nil, second.confirmedBackground != nil, seen.insert("confirmed").inserted {
                    settled.fulfill()
                }
            }
        }
        defer { observer.cancel() }
        await fulfillment(of: [submitted], timeout: 5)
        upload.open()
        await fulfillment(of: [attached], timeout: 5)
        patch.open()
        _ = try await delivery.value
        await fulfillment(of: [settled], timeout: 5)
        try await second.observeBackgroundChoice()
        _ = try await second.stageBackground(png)
        let next = try XCTUnwrap(second.pendingBackground)
        XCTAssertNotEqual(next.id, original.id)
        XCTAssertEqual(next.baseline, original.baseline + 1)
        XCTAssertEqual(f.wire.uploads.map(\.id), [original.id])
        XCTAssertEqual(f.wire.writes.map(\.id), [original.id])
        observer.cancel()
        await observer.value
    }

    func testLatePreviewAndReadErrorCannotReplaceNewlyStagedChoice() async throws {
        let gif = CardEditingImage(data: try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")),
                                   filename: "new.gif", mimeType: "image/gif")
        for lateError in [false, true] {
            let f = try await setupEditor()
            let editor = try await f.openEditor()
            try await editor.observeBackgroundChoice()
            _ = try await editor.stageBackground(png)
            let original = try XCTUnwrap(editor.pendingBackground)
            if lateError {
                let filename = try XCTUnwrap(original.image?.relativePath)
                let files = try XCTUnwrap(FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: nil)?.allObjects as? [URL])
                let retained = try XCTUnwrap(files.first { $0.lastPathComponent == filename })
                try Data("damaged original".utf8).write(to: retained)
            }
            let entered = expectation(description: "retained original bytes read before publication")
            let release = EditorExecutionGate()
            defer { release.open() }
            let previous = Task {
                try await editor.readBackground(readImage: { store, command in
                    let result: Result<CardEditingImage?, Error>
                    do {
                        result = .success(try await store.backgroundImage(command))
                        XCTAssertFalse(lateError)
                    } catch {
                        XCTAssertTrue(lateError)
                        XCTAssertEqual(error as? NoteLocalStoreError, .attachmentMismatch)
                        result = .failure(error)
                    }
                    entered.fulfill()
                    await release.wait()
                    return try result.get()
                }, restore: { _ in XCTFail("Published a previous choice or its read failure") })
            }
            await fulfillment(of: [entered], timeout: 5)
            try await editor.observeBackgroundChoice()
            _ = try await editor.stageBackground(gif)
            let replacement = try XCTUnwrap(editor.pendingBackground)
            XCTAssertNotEqual(replacement.id, original.id)
            release.open()
            do { _ = try await previous.value; XCTFail("Outdated preview was accepted") }
            catch is CancellationError {}
            XCTAssertEqual(editor.pendingBackground, replacement)
            XCTAssertFalse(editor.backgroundUnreadable)
            let current = try await editor.readBackground()
            guard case let .replace(selected) = current else { return XCTFail("Replacement disappeared") }
            XCTAssertEqual(selected.data, gif.data)
        }
    }

    func testSupersededReadAndRetiredGrantCannotPublishToMountedEditor() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        _ = try await editor.stageBackground(png)
        let target = try await f.library.backgroundTarget(identifier: "asset", createID: "unused", scope: f.scope)
        let original = try XCTUnwrap(editor.pendingBackground)
        for retire in [false, true] {
            let queued = expectation(description: "private queue held before reading")
            let admitted = expectation(description: "old read entered its admission check")
            let release = DispatchSemaphore(value: 0)
            let blocker = Task {
                try await target.store.transaction { _ in
                    queued.fulfill()
                    guard release.wait(timeout: .now() + 10) == .success else { throw NoteBackgroundError.unknown }
                }
            }
            await fulfillment(of: [queued], timeout: 5)
            let admission = editor.backgroundAdmission()
            f.nextAccessCheck = { admitted.fulfill() }
            let old = Task {
                try await editor.readBackground(admission: admission, restore: { _ in XCTFail("Superseded read overwrote visible state") })
            }
            await fulfillment(of: [admitted], timeout: 5)
            if retire { f.session += 1 }
            let newer = expectation(description: "successor read started before releasing the old one")
            f.nextAccessCheck = { newer.fulfill() }
            let fresh = Task { try await editor.readBackground() }
            await fulfillment(of: [newer], timeout: 5)
            release.signal()
            try await blocker.value
            do { _ = try await old.value; XCTFail("Superseded read applied") }
            catch is CancellationError {}
            catch NoteLocalStoreError.invalidScope {}
            _ = try await fresh.value
            XCTAssertEqual(editor.pendingBackground, original)
            XCTAssertFalse(editor.backgroundUnreadable)
        }
    }

    func testHeldUploadAllowsBodyCloseAndLateSessionCannotAttach() async throws {
        let f = try await setupEditor()
        let editor = try await f.openEditor()
        try await editor.observeBackgroundChoice()
        let intent = try await editor.stageBackground(png)
        let original = try XCTUnwrap(editor.pendingBackground)
        let gate = EditorExecutionGate()
        let entered = expectation(description: "upload awaits response")
        f.wire.onUpload = { entered.fulfill(); await gate.wait() }
        let pending = Task { try await editor.submitBackground(editor.backgroundAdmission()) }
        await fulfillment(of: [entered], timeout: 4)

        let note = try await editor.openExisting()
        let store = CardEditingStore(cardID: NoteLibraryStore.identifier(note), draft: .init(title: nil, content: note.body.content, tags: [], isPublic: true),
            backgroundMediaRef: nil, links: [], service: editor, preservesLocalDrafts: true)
        store.restoreStoredBackground(intent, confirmed: nil)
        let model = BlockNoteCardEditorModel(document: .init(contentJSON: nil, fallbackMarkdown: note.body.content))
        let persistence = LocalNoteEditorPersistenceSession(scope: f.scope, editingStore: store, bodyModel: model, isNew: false, initialIsPublic: true)
        model.controller.attach(drainAcceptedEvents: {
            _ = store.applyBodyRevision(content: "Later accepted edit", contentJSON: nil, revision: 9)
        }, commandHandler: { _ in })
        let closed = await persistence.closeForScopeChange()
        XCTAssertTrue(closed)
        XCTAssertEqual(f.library.notes.first?.body.content, "Later accepted edit")
        XCTAssertEqual(editor.pendingBackground?.id, original.id)
        f.session += 1
        f.accessScope = NoteStoreScope(actorID: "other-actor", environmentID: f.scope.environmentID)
        gate.open()
        do { _ = try await pending.value; XCTFail("Previous session attached") }
        catch NoteLocalStoreError.invalidScope {}
        XCTAssertTrue(f.wire.writes.isEmpty)
        XCTAssertEqual(f.library.notes.first?.body.content, "Later accepted edit")
        XCTAssertEqual(f.library.notes.first?.isPublic, true)
    }
}

@MainActor
private final class BackgroundEditorFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let scope: NoteStoreScope
    private let auth: AuthManager?
    init(auth: AuthManager?) {
        self.auth = auth
        scope = auth?.currentNoteScope ?? NoteStoreScope(actorID: UUID().uuidString, environmentID: "offline-background-tests")
    }
    let wire = BackgroundTestWire()
    let generation = NoteBackgroundGeneration(1)
    var session: UInt64 = 1 { didSet { generation.replace(with: session) } }
    var nextAccessCheck: (() -> Void)?
    lazy var accessScope = scope
    lazy var library = NoteLibraryStore(rootURL: root, service: { BackgroundNoteSource(scope: $0) })
    func openEditor() async throws -> LocalCoreCardEditingService {
        let editor = LocalCoreCardEditingService(identifier: "asset", creationID: UUID().uuidString, scope: scope, library: library,
            backgroundTransport: wire, backgroundGeneration: auth?.backgroundGeneration ?? generation, backgroundAccess: {
                let check = self.nextAccessCheck
                self.nextAccessCheck = nil
                check?()
                if let auth = self.auth {
                    return (auth.canOpenLocalNotes ? auth.currentNoteScope : nil, auth.sessionGeneration, auth.canEnterProduct)
                }
                return (self.accessScope, self.session, true)
            })
        _ = try await editor.openExisting()
        _ = try await editor.readBackground()
        return editor
    }
}

private actor BackgroundNoteSource: NoteSyncServing {
    let scope: NoteStoreScope
    private var token = "token"
    private var body = OfflineNoteBody(content: "Original body")
    init(scope: NoteStoreScope) { self.scope = scope }
    func manifest() async throws -> NoteSyncManifest {
        .init(protocolVersion: 3, complete: true, notes: [.init(assetID: "asset", syncToken: token, lifecycle: .active)])
    }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        .init(assetID: assetID, syncToken: token, body: body, lifecycle: .active, isPublic: true)
    }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt {
        guard operation.serverAssetID == "asset", let payload = try JSONSerialization.jsonObject(with: operation.requestBody) as? [String: Any],
              let content = payload["content"] as? String else { throw NoteSyncFailure.notReady }
        body = .init(content: content, contentJSON: payload["content_json"] as? String)
        token = UUID().uuidString
        return .init(operationID: operation.operationID, assetID: "asset", syncToken: token, noteDocumentVersionID: token, lifecycle: .active)
    }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}

@MainActor
private final class BackgroundTestWire: NoteBackgroundTransport {
    enum Loss { case upload, patch, remove }
    let ref = "med_1234567890abcdef"
    var current = NoteBackgroundObservation(revision: 0, displayRef: nil)
    var uploads: [NoteBackgroundCommand] = []
    var bytes: [Data] = []
    var writes: [NoteBackgroundCommand] = []
    var loss: Loss?
    var reads = 0
    var failRead = false
    var uploadError: NoteBackgroundError?
    var writeError: NoteBackgroundError?
    var onUpload: (() async -> Void)?
    var onWrite: (() async -> Void)?
    func backgroundObservation(scope: NoteStoreScope, asset: String) async throws -> NoteBackgroundObservation {
        reads += 1
        if failRead { throw NoteBackgroundError.unknown }
        return current
    }
    func uploadBackground(_ command: NoteBackgroundCommand, bytes: Data) async throws -> String {
        uploads.append(command); self.bytes.append(bytes)
        await onUpload?()
        if let uploadError { throw uploadError }
        if loss == .upload { loss = nil; throw NoteBackgroundError.unknown }
        return ref
    }
    func writeBackground(_ command: NoteBackgroundCommand) async throws -> NoteBackgroundObservation {
        writes.append(command)
        await onWrite?()
        if let writeError { throw writeError }
        let desired = command.logicalRef.map { "/api/v1/media/" + $0 + "/content?asset_id=asset" }
        if current.revision == command.baseline {
            current = .init(revision: command.baseline + 1, displayRef: desired)
        } else if current.revision != command.baseline + 1 || current.displayRef != desired {
            throw NoteBackgroundError.stale
        }
        if loss == .patch || loss == .remove { loss = nil; throw NoteBackgroundError.unknown }
        return current
    }
}
