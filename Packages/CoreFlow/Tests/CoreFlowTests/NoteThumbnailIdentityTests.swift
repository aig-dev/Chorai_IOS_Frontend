import XCTest
@testable import CoreFlow

@MainActor
final class NoteThumbnailIdentityTests: XCTestCase {
    func testIdentityUsesPublishedSnapshotWithoutRehydratingThePersistedBody() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = NoteStoreScope(actorID: "alice", environmentID: "local")
        let library = NoteLibraryStore(rootURL: root, service: { ThumbnailOfflineService(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        let photo = try await library.retainImage(.init(data: Data([1, 2, 3]), filename: "photo.png", mimeType: "image/png"), identifier: nil, createID: "one", scope: scope)
        let note = try await library.save(identifier: nil, createID: "one", body: .init(content: "photo", contentJSON: #"[{"type":"image","props":{"url":"\#(photo.url.absoluteString)"}}]"#), scope: scope)
        // An external damaged row makes any accidental identity-stage record
        // hydration fail. The library's already-published snapshot stays valid.
        let external = try await NoteLocalStore.open(rootURL: root, scope: scope)
        try await external.transaction { context in
            let row = try XCTUnwrap(NoteLocalStore.row(localID: "one", in: context))
            row.setValue(Data([0]), forKey: "payload")
        }
        try await external.close()
        let identity = try await library.thumbnailIdentity(source: .reference(photo.mediaRef), identifier: "local-note:one", scope: scope, bodyRevision: note.bodyRevision)
        XCTAssertEqual(identity.localID, "one")
        // Snapshot binding is not permission to bypass the bounded data read.
        do { _ = try await library.thumbnailData(for: identity); XCTFail("Damaged stored data accepted") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .corruptRecord) }
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testThumbnailIdentityBindsScopeBodyRevisionAndOriginalAttachment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = NoteStoreScope(actorID: "alice", environmentID: "local")
        let library = NoteLibraryStore(rootURL: root, service: { ThumbnailOfflineService(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        let photo = try await library.retainImage(.init(data: Data([1, 2, 3]), filename: "photo.png", mimeType: "image/png"), identifier: nil, createID: "one", scope: scope)
        let body = OfflineNoteBody(content: "photo", contentJSON: #"[{"id":"photo","type":"image","props":{"url":"\#(photo.url.absoluteString)"}}]"#)
        let note = try await library.save(identifier: nil, createID: "one", body: body, scope: scope)
        let identity = try await library.thumbnailIdentity(source: .reference(photo.mediaRef), identifier: "local-note:one", scope: scope, bodyRevision: note.bodyRevision)
        let equivalent = try await library.thumbnailIdentity(source: .previewURL(photo.url), identifier: "local-note:one", scope: scope, bodyRevision: note.bodyRevision)
        XCTAssertEqual(identity, equivalent)
        XCTAssertTrue(library.isCurrentThumbnail(identity))
        let bytes = try await library.thumbnailData(for: identity)
        XCTAssertEqual(bytes, Data([1, 2, 3]))
        _ = try await library.save(identifier: "local-note:one", createID: "one", body: .init(content: "photo removed"), scope: scope)
        XCTAssertFalse(library.isCurrentThumbnail(identity))
        do { _ = try await library.thumbnailData(for: identity); XCTFail("Old body identity accepted") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .staleGeneration) }
        await library.configure(scope: .init(actorID: "bob", environmentID: "local"), cloudEnabled: false)
        XCTAssertFalse(library.isCurrentThumbnail(identity))
        do { _ = try await library.thumbnailData(for: identity); XCTFail("Old account accepted") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidScope) }
        await library.configure(scope: nil, cloudEnabled: false)
    }
}

private struct ThumbnailOfflineService: NoteSyncServing {
    let scope: NoteStoreScope
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.notReady }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot { throw NoteSyncFailure.notReady }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.notReady }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}
