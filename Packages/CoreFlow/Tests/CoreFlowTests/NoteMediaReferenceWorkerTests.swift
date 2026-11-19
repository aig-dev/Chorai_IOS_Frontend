import XCTest
@testable import CoreFlow

@MainActor
final class NoteMediaReferenceWorkerTests: XCTestCase {
    func testRemotePreviewBindingHashesOffMainOnceAndLocalBindingNeedsNoHash() async throws {
        let probe = MediaReferenceProbe()
        let worker = NoteMediaReferenceWorker(parse: { try NoteSyncPayload.imageReferences($0) }, downloadID: { assetID, ref in
            probe.record(); return NoteAttachmentFiles.downloadID(assetID: assetID, mediaRef: ref)
        })
        let scope = NoteStoreScope(actorID: "alice", environmentID: "local")
        var note = OfflineNote(localID: "one", body: .init(content: "", contentJSON: #"[{"type":"image","props":{"mediaRef":"med_one"}},{"type":"image","props":{"mediaRef":"med_two"}}]"#))
        note.serverAssetID = "ast_one"
        let id = NoteAttachmentFiles.downloadID(assetID: "ast_one", mediaRef: "med_two")
        let url = try NoteAttachmentFiles.previewURL(uploadID: id)
        for _ in 0..<3 {
            let resolved = try await worker.previewURL(source: .previewURL(url), in: note, scope: scope)
            let reference = try await worker.remoteReference(previewUploadID: id, in: note, scope: scope)
            XCTAssertEqual(resolved, url); XCTAssertEqual(reference, "med_two")
        }
        XCTAssertEqual(probe.count, 2); XCTAssertFalse(probe.ranOnMain)
        note.attachments = [.init(uploadID: "local-photo", relativePath: "photo.data", originalFilename: "photo.png", mimeType: "image/png", sha256: "fixture", byteCount: 3, mediaRef: "med_two")]
        let localURL = try NoteAttachmentFiles.previewURL(uploadID: "local-photo")
        _ = try await worker.previewURL(source: .previewURL(localURL), in: note, scope: scope)
        XCTAssertEqual(probe.count, 2, "Owned local binding must bypass remote hashes")
        note.serverAssetID = "ast_replaced"
        let changed = try await worker.remoteReference(previewUploadID: id, in: note, scope: scope)
        XCTAssertNil(changed); XCTAssertEqual(probe.count, 4)
    }

    func testReferencesReuseExactBodyOffMainAndNeverAliasScopeOrChangedBody() async throws {
        let probe = MediaReferenceProbe()
        let worker = NoteMediaReferenceWorker(parse: { body in
            probe.record()
            return try NoteSyncPayload.imageReferences(body)
        })
        let scope = NoteStoreScope(actorID: "alice", environmentID: "local")
        var note = OfflineNote(localID: "one", body: .init(content: "", contentJSON: #"[{"type":"image","props":{"mediaRef":"med_one"}}]"#))
        let first = try await worker.references(in: note, scope: scope)
        let repeated = try await worker.references(in: note, scope: scope)
        XCTAssertEqual(first, ["med_one"])
        XCTAssertEqual(repeated, first)
        XCTAssertEqual(probe.count, 1)
        note.body = .init(content: "", contentJSON: #"[{"type":"image","props":{"mediaRef":"med_two"}}]"#)
        let changed = try await worker.references(in: note, scope: scope)
        XCTAssertEqual(changed, ["med_two"], "Exact body content matters even if a producer reuses a revision")
        _ = try await worker.references(in: note, scope: .init(actorID: "bob", environmentID: "local"))
        XCTAssertEqual(probe.count, 3)
        XCTAssertFalse(probe.ranOnMain)
    }

    func testOversizedReferenceInputsAreNotRetainedAndMalformedDocumentRemainsRetryable() async throws {
        let probe = MediaReferenceProbe()
        let worker = NoteMediaReferenceWorker(byteLimit: 1, parse: { body in
            probe.record(); return try NoteSyncPayload.imageReferences(body)
        })
        let scope = NoteStoreScope(actorID: "alice", environmentID: "local")
        let valid = OfflineNote(localID: "one", body: .init(content: "", contentJSON: "[]"))
        _ = try await worker.references(in: valid, scope: scope)
        _ = try await worker.references(in: valid, scope: scope)
        XCTAssertEqual(probe.count, 2)
        let broken = OfflineNote(localID: "one", body: .init(content: "", contentJSON: "{"))
        do { _ = try await worker.references(in: broken, scope: scope); XCTFail("Invalid input accepted") }
        catch { XCTAssertEqual(error as? NoteSyncFailure, .unsupportedDocument) }
        _ = try await worker.references(in: valid, scope: scope)
        XCTAssertEqual(probe.count, 4)
    }
}

private final class MediaReferenceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var main = false
    func record() { lock.lock(); defer { lock.unlock() }; calls += 1; main = main || Thread.isMainThread }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var ranOnMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
}
