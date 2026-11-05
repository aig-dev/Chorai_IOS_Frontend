import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteLibraryStoreTests: XCTestCase {
    private var root: URL!
    private let a = NoteStoreScope(actorID: "a", environmentID: "local")
    private let b = NoteStoreScope(actorID: "b", environmentID: "local")
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

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
        let current = try await library.open(identifier: id)
        do {
            try await library.discardConfirmedPurge(identifier: id, expectedGeneration: current.generation, scope: a)
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
