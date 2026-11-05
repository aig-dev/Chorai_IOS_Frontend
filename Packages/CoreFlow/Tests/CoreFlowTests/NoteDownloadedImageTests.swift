import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteDownloadedImageTests: XCTestCase {
    private var root: URL!
    private let scope = NoteStoreScope(actorID: "image-owner", environmentID: "local")
    private let ref = "med_0123456789abcdef"
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testRemoteImageDownloadsOnDemandOnceAndSurvivesOfflineReopen() async throws {
        let (library, transport, id) = try await fixture()
        let initial = try await library.open(identifier: id)
        let urls = try await library.imageDisplayURLs(identifier: id, scope: scope)
        let url = try XCTUnwrap(urls[ref].flatMap(URL.init(string:)))
        async let first = library.imagePreview(url, identifier: id, scope: scope)
        async let second = library.imagePreview(url, identifier: id, scope: scope)
        let previews = try await [first, second]
        XCTAssertEqual(previews.map(\.data), [Data([1, 2, 3]), Data([1, 2, 3])])
        let downloaded = try await library.open(identifier: id)
        XCTAssertEqual(downloaded.body, initial.body); XCTAssertEqual(downloaded.bodyRevision, initial.bodyRevision)
        XCTAssertTrue(downloaded.isSynchronized); XCTAssertEqual(downloaded.attachments.count, 1)
        let calls = await transport.downloads; XCTAssertEqual(calls, 1)
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: scope, cloudEnabled: false)
        let offline = try await library.imagePreview(url, identifier: id, scope: scope)
        XCTAssertEqual(offline.data, Data([1, 2, 3]))
        let laterCalls = await transport.downloads; XCTAssertEqual(laterCalls, 1)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testFailedImageDownloadKeepsTheNoteAndAllowsTextSave() async throws {
        let (library, transport, id) = try await fixture()
        await transport.failDownloads()
        let urls = try await library.imageDisplayURLs(identifier: id, scope: scope)
        let url = try XCTUnwrap(urls[ref].flatMap(URL.init(string:)))
        do { _ = try await library.imagePreview(url, identifier: id, scope: scope); XCTFail("Download must fail") }
        catch { XCTAssertEqual(error as? NoteSyncFailure, .permissionDenied) }
        let original = try await library.open(identifier: id)
        XCTAssertTrue(original.attachments.isEmpty)
        let runtimeJSON = try XCTUnwrap(original.body.contentJSON).replacingOccurrences(of: "\"mediaRef\":", with: "\"url\":\"\(url.absoluteString)\",\"mediaRef\":")
        let saved = try await library.save(identifier: id, createID: "unused", body: OfflineNoteBody(content: "new text", contentJSON: runtimeJSON), scope: scope)
        XCTAssertEqual(saved.body.content, "new text"); XCTAssertEqual(saved.body.contentJSON, runtimeJSON)
        let frozen = try XCTUnwrap(NoteSyncPayload.operation(for: saved, operationID: "text-edit"))
        XCTAssertTrue(frozen.attachments.isEmpty)
        XCTAssertFalse(String(decoding: frozen.requestBody, as: UTF8.self).contains(NoteAttachmentFiles.previewScheme))
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testLateImageDownloadCannotEnterAnotherAccountsStoreOrReturnBytes() async throws {
        let (library, transport, id) = try await fixture()
        await transport.holdDownloads()
        let urls = try await library.imageDisplayURLs(identifier: id, scope: scope)
        let url = try XCTUnwrap(urls[ref].flatMap(URL.init(string:)))
        let request = Task { try await library.imagePreview(url, identifier: id, scope: scope) }
        for _ in 0..<100 {
            if await transport.isWaiting { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let started = await transport.isWaiting; XCTAssertTrue(started)
        await library.configure(scope: nil, cloudEnabled: false)
        await transport.releaseDownload()
        do { _ = try await request.value; XCTFail("Closed scope must not return private image bytes") }
        catch { XCTAssertTrue(error is CancellationError || error as? NoteLocalStoreError == .invalidScope) }
        await library.configure(scope: scope, cloudEnabled: false)
        let reopened = try await library.open(identifier: id)
        XCTAssertTrue(reopened.attachments.isEmpty)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testConflictCopyUsesDownloadedBytesOfflineAndGetsNewUploadIdentity() async throws {
        let (library, transport, id) = try await fixture()
        let urls = try await library.imageDisplayURLs(identifier: id, scope: scope)
        let url = try XCTUnwrap(urls[ref].flatMap(URL.init(string:)))
        _ = try await library.imagePreview(url, identifier: id, scope: scope)
        let original = try await library.open(identifier: id)
        await library.configure(scope: nil, cloudEnabled: false)
        let disk = try await NoteLocalStore.open(rootURL: root, scope: scope)
        _ = try await disk.mutate(localID: original.localID) { note in
            note.syncIssue = "conflict"
            note.remoteSnapshot = NoteRemoteSnapshot(assetID: "asset", syncToken: "changed", body: OfflineNoteBody(content: "cloud"), lifecycle: .active, isPublic: true)
        }
        try await disk.close()
        await transport.failDownloads()
        await library.configure(scope: scope, cloudEnabled: false)
        let copy = try await library.saveLocalAsNewNote(identifier: id)
        XCTAssertFalse(copy.isPublic); XCTAssertNil(copy.serverAssetID)
        let image = try XCTUnwrap(copy.attachments.first)
        XCTAssertNil(image.mediaRef); XCTAssertNotEqual(image.uploadID, original.attachments.first?.uploadID)
        XCTAssertTrue(copy.body.contentJSON?.contains(NoteSyncPayload.localMediaRef(uploadID: image.uploadID)) == true)
        let calls = await transport.downloads; XCTAssertEqual(calls, 1)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    private func fixture() async throws -> (NoteLibraryStore, ImageDownloadTransport, String) {
        let raw = "{\"schema_version\":1,\"editor_kind\":\"blocknote\",\"blocks\":[{\"id\":\"image\",\"type\":\"image\",\"props\":{\"mediaRef\":\"\(ref)\"}}]}"
        let disk = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let applied = try await disk.applyRemote(NoteRemoteSnapshot(assetID: "asset", syncToken: "token", body: OfflineNoteBody(content: "text", contentJSON: raw), lifecycle: .active, isPublic: false), localID: nil, expectedGeneration: nil)
        let note = try XCTUnwrap(applied)
        try await disk.close()
        let transport = ImageDownloadTransport(scope: scope)
        let library = NoteLibraryStore(rootURL: root, service: { _ in transport })
        await library.configure(scope: scope, cloudEnabled: true)
        return (library, transport, NoteLibraryStore.identifier(note))
    }
}

private actor ImageDownloadTransport: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    var downloads = 0
    var isWaiting: Bool { waiting != nil }
    private var failure = false
    private var hold = false
    private var waiting: CheckedContinuation<Void, Never>?
    init(scope: NoteStoreScope) { self.scope = scope }
    func failDownloads() { failure = true }
    func holdDownloads() { hold = true }
    func releaseDownload() { waiting?.resume(); waiting = nil }
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.transient(retryAfter: nil) }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot { throw NoteSyncFailure.notFound }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.notReady }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment {
        downloads += 1
        if failure { throw NoteSyncFailure.permissionDenied }
        if hold { await withCheckedContinuation { waiting = $0 } }
        else { try await Task.sleep(nanoseconds: 15_000_000) }
        return NoteSyncDownloadedAttachment(data: Data([1, 2, 3]), filename: "remote.png", mimeType: "image/png")
    }
}
