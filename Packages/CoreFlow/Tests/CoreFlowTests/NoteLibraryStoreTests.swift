import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteLibraryStoreTests: XCTestCase {
    private var root: URL!
    private let a = NoteStoreScope(actorID: "a", environmentID: "local")
    private let b = NoteStoreScope(actorID: "b", environmentID: "local")
    override func setUp() async throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testConcurrentSynchronizationKeepsExistingSingleFlight() async throws {
        let service = LibraryManifestGate(scope: a)
        let library = NoteLibraryStore(rootURL: root, service: { _ in service })
        await library.configure(scope: a, cloudEnabled: true)
        let first = Task { await library.synchronize(forceRetry: true) }
        let second = Task { await library.synchronize(forceRetry: true) }
        await service.waitUntilEntered()
        // Both callers have a chance to reach the coordinator while the manifest is held.
        let joined = expectation(description: "second waiter joined")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { joined.fulfill() }
        await fulfillment(of: [joined], timeout: 1)
        await service.finish()
        await first.value; await second.value
        let calls = await service.count
        XCTAssertEqual(calls, 1)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testConcurrentMissingNoteOpensShareDownloadAndOneCancellationDoesNotCancelOthers() async throws {
        let started = expectation(description: "detail started")
        let duplicate = expectation(description: "no duplicate detail"); duplicate.isInverted = true
        let service = LibraryOpenTransport(scope: a, onDetail: { count in
            if count == 1 { started.fulfill() } else { duplicate.fulfill() }
        })
        let library = NoteLibraryStore(rootURL: root, service: { _ in service })
        await library.configure(scope: a, cloudEnabled: true)
        var updates = 0
        let subscription = library.changes.sink { if case .updated = $0 { updates += 1 } }
        defer { subscription.cancel() }
        let first = Task { try await library.open(identifier: "asset", scope: a) }
        let second = Task { try await library.open(identifier: "asset", scope: a) }
        await fulfillment(of: [started, duplicate], timeout: 0.1)
        first.cancel()
        await service.finish()
        let note = try await second.value
        XCTAssertEqual(note.serverAssetID, "asset")
        do { _ = try await first.value; XCTFail("Cancelled consumer received a note") }
        catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertEqual(updates, 1)
        let count = await service.count
        XCTAssertEqual(count, 1)
        _ = try await library.open(identifier: "asset", scope: a)
        let cachedCount = await service.count
        XCTAssertEqual(cachedCount, 1)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testMissingNoteFailureCanRetryAndRetiredScopeCannotPublishLateDownload() async throws {
        let service = LibraryOpenTransport(scope: a)
        let library = NoteLibraryStore(rootURL: root, service: { _ in service })
        await library.configure(scope: a, cloudEnabled: true)
        let first = Task { try await library.open(identifier: "asset", scope: a) }
        await service.waitForCount(1)
        await service.finish(error: .notFound)
        do { _ = try await first.value; XCTFail("Expected failed read") }
        catch { XCTAssertEqual(error as? NoteSyncFailure, .notFound) }
        let retry = Task { try await library.open(identifier: "asset", scope: a) }
        await service.waitForCount(2)
        await library.configure(scope: b, cloudEnabled: false)
        await service.finish()
        do { _ = try await retry.value; XCTFail("Retired scope published a note") } catch {}
        XCTAssertTrue(library.notes.isEmpty)
        XCTAssertEqual(library.scope, b)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testOlderAudienceReadCannotOverwriteAConfirmedPublication() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: a)
        let snapshot = NoteRemoteSnapshot(assetID: "shared", syncToken: "base", body: OfflineNoteBody(content: "saved"),
                                          lifecycle: .active, isPublic: false)
        let inserted = try await store.applyRemote(snapshot, localID: nil, expectedGeneration: nil)
        let initial = try XCTUnwrap(inserted)
        try await store.close()
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        let confirmed = try await library.recordMetadata(identifier: "shared", isPublic: true, scope: a)
        do {
            _ = try await library.recordMetadata(identifier: "shared", isPublic: false, scope: a,
                                                 expectedGeneration: initial.generation)
            XCTFail("An older owner GET replaced confirmed metadata")
        } catch NoteLocalStoreError.staleGeneration {}
        let retained = try await library.open(identifier: "shared")
        XCTAssertEqual(retained, confirmed)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testLocalCreateEditReopenNeverRequiresCloudAndUsesStableIdentity() async throws {
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        let first = try await library.save(identifier: nil, createID: "stable", body: OfflineNoteBody(content: "first"))
        let later = try await library.save(identifier: NoteLibraryStore.identifier(first), createID: "ignored", body: OfflineNoteBody(content: "later"))
        XCTAssertEqual(first.localID, later.localID)
        XCTAssertEqual(library.notes.count, 1)
        await library.configure(scope: nil, cloudEnabled: false)
        XCTAssertTrue(library.notes.isEmpty)
        await library.configure(scope: a, cloudEnabled: false)
        XCTAssertEqual(library.notes.first?.body.content, "later")
        XCTAssertEqual(library.notes.first?.localID, first.localID)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testAccountAndEnvironmentChangesHideRetainedNotesAndRejectOldEditorScope() async throws {
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        let first = try await library.save(identifier: nil, createID: "one", body: OfflineNoteBody(content: "private A"), scope: a)
        await library.configure(scope: b, cloudEnabled: false)
        XCTAssertTrue(library.notes.isEmpty)
        do {
            _ = try await library.save(identifier: NoteLibraryStore.identifier(first), createID: "one", body: OfflineNoteBody(content: "stale A"), scope: a)
            XCTFail("An old editor cannot write into B's store")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidScope) }
        await library.configure(scope: NoteStoreScope(actorID: "a", environmentID: "production"), cloudEnabled: false)
        XCTAssertTrue(library.notes.isEmpty)
        await library.configure(scope: a, cloudEnabled: false)
        XCTAssertEqual(library.notes.first?.body.content, "private A")
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testFirstAutosaveAndPhotoShareOneDurableOfflineDraft() async throws {
        let a = a
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        let image = CardEditingImage(data: Data([1, 3, 5]), filename: "first.png", mimeType: "image/png")
        var savedPhotos: [(String, URL)] = []
        for index in 0..<12 {
            let id = "first-\(index)"
            let body = OfflineNoteBody(content: "offline text \(index)")
            async let typing = library.save(identifier: nil, createID: id, body: body, scope: a)
            async let takingPhoto = library.retainImage(image, identifier: nil, createID: id, scope: a)
            let (saved, photo) = try await (typing, takingPhoto)
            let stored = try await library.open(identifier: NoteLibraryStore.identifier(saved))
            XCTAssertEqual(stored.body, body)
            XCTAssertEqual(stored.attachments.count, 1)
            XCTAssertEqual(library.notes.first { $0.localID == id }, stored)
            let raw = #"[{"id":"image","type":"image","props":{"url":"\#(photo.url.absoluteString)"}}]"#
            _ = try await library.save(identifier: nil, createID: id, body: OfflineNoteBody(content: body.content, contentJSON: raw), scope: a)
            savedPhotos.append((NoteLibraryStore.identifier(saved), photo.url))
        }
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: a, cloudEnabled: false)
        XCTAssertEqual(library.notes.count, savedPhotos.count)
        for (identifier, url) in savedPhotos {
            let stored = try await library.open(identifier: identifier)
            let ref = NoteSyncPayload.localMediaRef(uploadID: try NoteAttachmentFiles.previewUploadID(url))
            XCTAssertTrue(stored.body.contentJSON?.contains(ref) == true)
            let preview = try await library.imagePreview(url, identifier: identifier, scope: a)
            XCTAssertEqual(preview.data, image.data)
        }
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testEditingUnavailableRemoteNotePreservesDeferredConflictAfterRelaunch() async throws {
        let disk = try await NoteLocalStore.open(rootURL: root, scope: a)
        let snapshot = NoteRemoteSnapshot(assetID: "gone", syncToken: "v1", body: OfflineNoteBody(content: "first"),
                                          lifecycle: .active, isPublic: false)
        let remote = try await disk.applyRemote(snapshot, localID: nil, expectedGeneration: nil)
        let note = try XCTUnwrap(remote)
        try await disk.recordSyncIssue(localID: note.localID, issue: "remote_unavailable")
        try await disk.close()
        let library = library()
        let id = NoteLibraryStore.identifier(note)
        await library.configure(scope: a, cloudEnabled: false)
        _ = try await library.save(identifier: id, createID: "unused", body: OfflineNoteBody(content: "still mine"), scope: a)
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: a, cloudEnabled: false)
        let saved = try await library.open(identifier: id)
        XCTAssertEqual(saved.body.content, "still mine")
        XCTAssertEqual(saved.syncIssue, "remote_unavailable")
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testLibraryPublishesOnlyCommittedRowsUntilTheAccountIsReplaced() async throws {
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        var changes: [[String]] = []
        let subscription = library.changes.sink { change in
            switch change {
            case .background: break
            case .reset: changes.append(["reset"])
            case let .updated(notes, removed):
                changes.append(notes.map(\.localID).sorted() + removed.sorted())
            }
        }
        defer { subscription.cancel() }
        let one = try await library.save(identifier: nil, createID: "one", body: OfflineNoteBody(content: "one"))
        _ = try await library.save(identifier: nil, createID: "two", body: OfflineNoteBody(content: "two"))
        let id = NoteLibraryStore.identifier(one)
        let edited = try await library.save(identifier: id, createID: "", body: OfflineNoteBody(content: "changed"))
        _ = try await library.save(identifier: id, createID: "", body: edited.body)
        try await library.setLifecycle(identifier: id, lifecycle: .trashed)
        XCTAssertEqual(changes, [["one"], ["two"], ["one"], ["one"]])
        XCTAssertEqual(library.notes.map(\.localID), ["one", "two"])
        XCTAssertEqual(library.notes.first?.desiredLifecycle, .trashed)
        let countBeforeSwitch = changes.count
        await library.configure(scope: b, cloudEnabled: false)
        XCTAssertEqual(changes.last, ["reset"])
        XCTAssertEqual(changes.count, countBeforeSwitch + 1)
        XCTAssertTrue(library.notes.isEmpty)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testConfirmedPurgePublishesOnlyTheRemovedID() async throws {
        let disk = try await NoteLocalStore.open(rootURL: root, scope: a)
        let snapshot = NoteRemoteSnapshot(assetID: "trash", syncToken: "v1", body: OfflineNoteBody(content: "trashed"),
                                          lifecycle: .trashed, isPublic: false)
        let seeded = try await disk.applyRemote(snapshot, localID: nil, expectedGeneration: nil)
        let note = try XCTUnwrap(seeded)
        try await disk.close()
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        let keep = try await library.save(identifier: nil, createID: "keep", body: OfflineNoteBody(content: "keep"))
        let attempt = try await library.beginPurge(identifier: "trash", baseSyncToken: "v1", scope: a)
        var removedIDs = Set<String>()
        let subscription = library.changes.sink { change in
            if case let .updated(updated, removed) = change {
                XCTAssertTrue(updated.isEmpty)
                removedIDs.formUnion(removed)
            }
        }
        defer { subscription.cancel() }
        let receipt = NotePurgeWriteReceipt(assetID: "trash", requestID: attempt.requestID, state: "ERASED",
            activityID: "activity", actionLogID: "log", certificateID: "certificate", cleanupState: .pending)
        try await library.confirmPurge(attempt, receipt: receipt)
        XCTAssertEqual(removedIDs, [note.localID])
        XCTAssertEqual(library.notes, [keep])
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testRevalidationSuspendsCloudWithoutUnmountingLibraryAndRefreshKeepsDraft() async throws {
        let service = LibraryUnavailableTransport(scope: a)
        let library = NoteLibraryStore(rootURL: root, service: { _ in service })
        await library.configure(scope: a, cloudEnabled: false)
        let note = try await library.save(identifier: nil, createID: "saved", body: OfflineNoteBody(content: "retained"))
        await library.configure(scope: a, cloudEnabled: true)
        await library.synchronize()
        XCTAssertEqual(library.notes.first?.body.content, "retained")
        await library.configure(scope: a, cloudEnabled: false)
        let loaded = try await library.open(identifier: NoteLibraryStore.identifier(note))
        XCTAssertEqual(loaded.body.content, "retained")
        XCTAssertEqual(library.scope, a)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testAttachmentBytesAndIdentityPersistBeforeDocumentCanReferenceThem() async throws {
        let library = library()
        await library.configure(scope: a, cloudEnabled: false)
        let image = CardEditingImage(data: Data([1, 3, 5]), filename: "photo.png", mimeType: "image/png")
        let upload = try await library.retainImage(image, identifier: nil, createID: "draft", scope: a)
        XCTAssertEqual(upload.url.scheme, "chorai-note-media")
        let raw = "{\"blocks\":[{\"type\":\"image\",\"props\":{\"mediaRef\":\"\(upload.mediaRef)\"}}]}"
        let note = try await library.save(identifier: nil, createID: "draft", body: OfflineNoteBody(content: "image", contentJSON: raw), scope: a)
        XCTAssertEqual(note.attachments.count, 1)
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: a, cloudEnabled: false)
        XCTAssertEqual(library.notes.first?.body.contentJSON, raw)
        XCTAssertEqual(library.notes.first?.attachments.first?.uploadID, note.attachments.first?.uploadID)
        let preview = try await library.imagePreview(upload.url, identifier: NoteLibraryStore.identifier(note), scope: a)
        XCTAssertEqual(preview.data, image.data)
        XCTAssertEqual(preview.mimeType, image.mimeType)
        let urls = try await library.imageDisplayURLs(identifier: NoteLibraryStore.identifier(note), scope: a)
        XCTAssertEqual(urls[upload.mediaRef], upload.url.absoluteString)
        await library.configure(scope: b, cloudEnabled: false)
        do {
            _ = try await library.imagePreview(upload.url, identifier: NoteLibraryStore.identifier(note), scope: a)
            XCTFail("A closed account cannot serve image bytes")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidScope) }
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testImageInsertedByURLKeepsRetainedIdentityAndUnknownFieldsAfterRestart() async throws {
        let library = library(); await library.configure(scope: a, cloudEnabled: false)
        let upload = try await library.retainImage(CardEditingImage(data: Data([1, 2, 3]), filename: "a.png", mimeType: "image/png"), identifier: nil, createID: "draft", scope: a)
        let raw = "{\"future\":{\"keep\":true},\"blocks\":[{\"id\":\"image\",\"type\":\"image\",\"props\":{\"url\":\"\(upload.url.absoluteString)\",\"caption\":\"keep\"}}]}"
        _ = try await library.save(identifier: nil, createID: "draft", body: OfflineNoteBody(content: "image", contentJSON: raw), scope: a)
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: a, cloudEnabled: false)
        let saved = try XCTUnwrap(library.notes.first)
        let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(saved.body.contentJSON).utf8)) as? [String: Any])
        let props = try XCTUnwrap((document["blocks"] as? [[String: Any]])?.first?["props"] as? [String: Any])
        XCTAssertEqual(props["mediaRef"] as? String, upload.mediaRef)
        XCTAssertEqual(props["caption"] as? String, "keep")
        XCTAssertEqual((document["future"] as? [String: Bool])?["keep"], true)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testAnotherNotesPreviewCannotAuthorizeAnAttachmentReference() async throws {
        let library = library(); await library.configure(scope: a, cloudEnabled: false)
        let upload = try await library.retainImage(CardEditingImage(data: Data([4]), filename: "a.png", mimeType: "image/png"), identifier: nil, createID: "owner", scope: a)
        let raw = "{\"blocks\":[{\"type\":\"image\",\"props\":{\"url\":\"\(upload.url.absoluteString)\"}}]}"
        do {
            _ = try await library.save(identifier: nil, createID: "other", body: OfflineNoteBody(content: "forged", contentJSON: raw), scope: a)
            XCTFail("A preview from another note cannot create a saved image reference")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidAttachment) }
        XCTAssertEqual(library.notes.map(\.localID), ["owner"])
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testNativeArrayImageKeepsItsIdentityBytesAndLifecycleAcrossRestart() async throws {
        let library = library(); await library.configure(scope: a, cloudEnabled: false)
        let bytes = Data([4, 3, 2, 1])
        let upload = try await library.retainImage(CardEditingImage(data: bytes, filename: "native.png", mimeType: "image/png"), identifier: nil, createID: "native", scope: a)
        let raw = "[{\"id\":\"photo\",\"type\":\"image\",\"props\":{\"url\":\"\(upload.url.absoluteString)\",\"caption\":\"keep caption\"},\"children\":[]}]"
        let note = try await library.save(identifier: nil, createID: "native", body: OfflineNoteBody(content: "photo", contentJSON: raw), scope: a)
        let id = NoteLibraryStore.identifier(note)
        try await library.setLifecycle(identifier: id, lifecycle: .trashed)
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: a, cloudEnabled: false)
        let reopened = try await library.open(identifier: id)
        XCTAssertEqual(reopened.desiredLifecycle, .trashed)
        let blocks = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(reopened.body.contentJSON).utf8)) as? [[String: Any]])
        let props = try XCTUnwrap(blocks.first?["props"] as? [String: Any])
        XCTAssertEqual(props["mediaRef"] as? String, upload.mediaRef)
        XCTAssertEqual(props["caption"] as? String, "keep caption")
        try await library.setLifecycle(identifier: id, lifecycle: .active)
        let preview = try await library.imagePreview(upload.url, identifier: id, scope: a)
        XCTAssertEqual(preview.data, bytes)
        let restored = try await library.open(identifier: id)
        XCTAssertEqual(restored.body, reopened.body)
        XCTAssertEqual(restored.desiredLifecycle, .active)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testNativeArrayCannotSaveAnotherNotesPreview() async throws {
        let library = library(); await library.configure(scope: a, cloudEnabled: false)
        let upload = try await library.retainImage(CardEditingImage(data: Data([1]), filename: "owned.png", mimeType: "image/png"), identifier: nil, createID: "owner", scope: a)
        let raw = "[{\"id\":\"photo\",\"type\":\"image\",\"props\":{\"url\":\"\(upload.url.absoluteString)\"},\"children\":[]}]"
        do {
            _ = try await library.save(identifier: nil, createID: "other", body: OfflineNoteBody(content: "forged", contentJSON: raw), scope: a)
            XCTFail("Another note's local preview cannot authorize this image")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidAttachment) }
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testPreviewURLRejectsPathAndAuthorityAliases() throws {
        let canonical = try NoteAttachmentFiles.previewURL(uploadID: "abc-123")
        XCTAssertEqual(try NoteAttachmentFiles.previewUploadID(canonical), "abc-123")
        for raw in ["chorai-note-media://other/abc-123", "chorai-note-media://attachment/abc-123?token=x", "chorai-note-media://attachment/abc-123#x", "chorai-note-media://user@attachment/abc-123", "chorai-note-media://attachment:80/abc-123", "chorai-note-media://attachment/%61bc-123", "chorai-note-media://attachment/../abc-123", "file:///abc-123"] {
            XCTAssertThrowsError(try NoteAttachmentFiles.previewUploadID(XCTUnwrap(URL(string: raw))), raw)
        }
    }

    func testFrozenImagePayloadReplacesOnlyItsOwnPreviewAndReference() throws {
        let files = try NoteAttachmentFiles(directoryURL: root)
        var attachment = try files.retain(data: Data([1]), filename: "a.png", mimeType: "image/png")
        attachment.mediaRef = "med_0123456789abcdef"
        let preview = try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID)
        for ref in [NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID), try XCTUnwrap(attachment.mediaRef)] {
            let raw = "{\"blocks\":[{\"type\":\"image\",\"props\":{\"mediaRef\":\"\(ref)\",\"url\":\"\(preview)\",\"caption\":\"preserved\"}}]}"
            let remote = try NoteSyncPayload.remoteDocument(body: OfflineNoteBody(content: "image", contentJSON: raw), attachments: [attachment])
            XCTAssertFalse(remote.contains(NoteAttachmentFiles.previewScheme))
            XCTAssertFalse(remote.contains("local-note-attachment:"))
            XCTAssertTrue(remote.contains("med_0123456789abcdef")); XCTAssertTrue(remote.contains("preserved"))
        }
    }

    func testDeleteRetainsDirtyBodyAndRestoreIsLocalWhileOffline() async throws {
        let library = library(); await library.configure(scope: a, cloudEnabled: false)
        let note = try await library.save(identifier: nil, createID: "trash", body: OfflineNoteBody(content: "do not publish"))
        let id = NoteLibraryStore.identifier(note)
        try await library.setLifecycle(identifier: id, lifecycle: .trashed)
        XCTAssertEqual(library.notes.first?.desiredLifecycle, .trashed)
        XCTAssertEqual(library.notes.first?.body.content, "do not publish")
        try await library.setLifecycle(identifier: id, lifecycle: .active)
        XCTAssertEqual(library.notes.first?.desiredLifecycle, .active)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    private func library() -> NoteLibraryStore {
        NoteLibraryStore(rootURL: root, service: { LibraryUnavailableTransport(scope: $0) })
    }

    func testPermanentCloudDeletionCannotEraseUnsyncedLocalBody() async throws {
        let library = library(); await library.configure(scope: a, cloudEnabled: false)
        let note = try await library.save(identifier: nil, createID: "keep", body: OfflineNoteBody(content: "retained"))
        let id = NoteLibraryStore.identifier(note)
        try await library.setLifecycle(identifier: id, lifecycle: .trashed)
        do {
            _ = try await library.beginPurge(identifier: id, baseSyncToken: "cloud", scope: a)
            XCTFail("A cloud deletion must never confirm unsent local body")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidOperation) }
        XCTAssertEqual(library.notes.first?.body.content, "retained")
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testBufferedEditorInputCannotSilentlyRebaseOntoAnUnseenCloudPull() async throws {
        let disk = try await NoteLocalStore.open(rootURL: root, scope: a)
        let original = NoteRemoteSnapshot(assetID: "asset", syncToken: "before", body: OfflineNoteBody(content: "original"), lifecycle: .active, isPublic: false)
        let fetched = try await disk.applyRemote(original, localID: nil, expectedGeneration: nil)
        let opened = try XCTUnwrap(fetched)
        let newer = NoteRemoteSnapshot(assetID: "asset", syncToken: "after", body: OfflineNoteBody(content: "web edit"), lifecycle: .active, isPublic: true)
        _ = try await disk.applyRemote(newer, localID: opened.localID, expectedGeneration: opened.generation)
        let saved = try await disk.saveBody(localID: opened.localID, body: OfflineNoteBody(content: "user was already typing"), observedBodyRevision: opened.bodyRevision)
        XCTAssertEqual(saved.body.content, "user was already typing")
        XCTAssertEqual(saved.remoteSnapshot?.body.content, "web edit")
        XCTAssertEqual(saved.remoteSnapshot?.syncToken, "after")
        XCTAssertEqual(saved.syncIssue, "conflict")
        try await disk.close()
    }
}

private struct LibraryUnavailableTransport: NoteSyncServing {
    let scope: NoteStoreScope
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.transient(retryAfter: nil) }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot { throw NoteSyncFailure.transient(retryAfter: nil) }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.transient(retryAfter: nil) }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.transient(retryAfter: nil) }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.transient(retryAfter: nil) }
}

private actor LibraryOpenTransport: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    private(set) var count = 0
    private let onDetail: @Sendable (Int) -> Void
    private var continuations: [CheckedContinuation<Void, Error>] = []
    init(scope: NoteStoreScope, onDetail: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.scope = scope; self.onDetail = onDetail
    }
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.notReady }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        count += 1; onDetail(count)
        try await withCheckedThrowingContinuation { continuations.append($0) }
        return .init(assetID: assetID, syncToken: "v1", body: .init(content: "downloaded"), lifecycle: .active, isPublic: false)
    }
    func waitForCount(_ target: Int) async { while count < target { await Task.yield() } }
    func finish(error: NoteSyncFailure? = nil) {
        let pending = continuations; continuations = []
        for continuation in pending {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.notReady }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}

private actor LibraryManifestGate: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    private(set) var count = 0
    private var pending: [CheckedContinuation<Void, Never>] = []
    init(scope: NoteStoreScope) { self.scope = scope }
    func manifest() async throws -> NoteSyncManifest {
        count += 1
        await withCheckedContinuation { pending.append($0) }
        return .init(protocolVersion: 1, complete: true, notes: [])
    }
    func waitUntilEntered() async { while count == 0 { await Task.yield() } }
    func finish() { let waits = pending; pending = []; waits.forEach { $0.resume() } }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot { throw NoteSyncFailure.notReady }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.notReady }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}
