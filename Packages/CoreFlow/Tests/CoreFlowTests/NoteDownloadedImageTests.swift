import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteDownloadedImageTests: XCTestCase {
    private var root: URL!
    private let scope = NoteStoreScope(actorID: "image-owner", environmentID: "local")
    private let ref = "med_0123456789abcdef"
    override func setUp() async throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testPersonalThumbnailAndEditorShareOneVerifiedDownloadByLocalOrServerID() async throws {
        let hydratedURL = "https://stale.example/remote.png"
        let (library, transport, id) = try await fixture(responseURL: hydratedURL)
        let note = try await library.open(identifier: id)
        let displayURLs = try await library.imageDisplayURLs(identifier: "asset", scope: scope)
        let editorURL = try XCTUnwrap(displayURLs[ref].flatMap(URL.init(string:)))
        let publicPreview = LibraryCardPreviewParser.parse(content: note.body.content, contentJSON: note.body.contentJSON)
        XCTAssertEqual(publicPreview.imageSource, hydratedURL)

        let personal = LibraryCardPreviewParser.parse(content: note.body.content, contentJSON: note.body.contentJSON, allowsLocalImages: true)
        XCTAssertEqual(personal.imageMediaRef, ref)
        let downloaded = try await library.imagePreview(editorURL, identifier: "asset", scope: scope)
        XCTAssertEqual(downloaded.data, Data([1, 2, 3]))

        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: scope, cloudEnabled: false)
        let offlineURLs = try await library.imageDisplayURLs(identifier: id, scope: scope)
        let thumbnailRef = try XCTUnwrap(personal.imageMediaRef)
        let thumbnailURL = try XCTUnwrap(offlineURLs[thumbnailRef].flatMap(URL.init(string:)))
        let reopened = try await library.imagePreview(thumbnailURL, identifier: id, scope: scope)
        XCTAssertEqual(reopened.data, Data([1, 2, 3]))
        let laterCalls = await transport.downloads
        XCTAssertEqual(laterCalls, 1)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testUncachedOwnedSearchImageOpensOnlineAndStaysAvailableOnlyInItsAccount() async throws {
        let scope = scope
        let raw = #"[{"id":"photo","type":"image","props":{"mediaRef":"\#(ref)","url":"https://stale.example/photo.png"}}]"#
        let searchNote = NoteRemoteSnapshot(assetID: "search-note", syncToken: "search-version",
                                            body: OfflineNoteBody(content: "", contentJSON: raw), lifecycle: .active, isPublic: false)
        let otherScope = NoteStoreScope(actorID: "another-reader", environmentID: "local")
        let transport = ImageDownloadTransport(scope: scope, searchNote: searchNote)
        let otherTransport = ImageDownloadTransport(scope: otherScope)
        let library = NoteLibraryStore(rootURL: root, service: { $0 == otherScope ? otherTransport : transport })
        await library.configure(scope: scope, cloudEnabled: true)
        XCTAssertTrue(library.notes.isEmpty)

        async let search = library.imageDisplayURLs(identifier: "search-note", scope: scope)
        async let otherReader = library.imageDisplayURLs(identifier: "search-note", scope: scope)
        let (first, second) = try await (search, otherReader)
        let url = try XCTUnwrap(first[ref].flatMap(URL.init(string:)))
        XCTAssertEqual(second[ref], url.absoluteString)
        let photo = try await library.imagePreview(url, identifier: "search-note", scope: scope)
        XCTAssertEqual(photo.data, Data([1, 2, 3]))

        await library.configure(scope: otherScope, cloudEnabled: false)
        do {
            _ = try await library.imagePreview(url, identifier: "search-note", scope: scope)
            XCTFail("A previous account's photo request must expire")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidScope) }
        do {
            _ = try await library.imagePreview(url, identifier: "search-note", scope: otherScope)
            XCTFail("Another account must not be able to use a copied photo URL")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidAttachment) }
        await library.configure(scope: scope, cloudEnabled: false)
        let localNote = try XCTUnwrap(library.notes.first)
        let offline = try await library.imagePreview(url, identifier: NoteLibraryStore.identifier(localNote), scope: scope)
        XCTAssertEqual(offline.data, Data([1, 2, 3]))
        let downloads = await transport.downloads
        XCTAssertEqual(downloads, 1)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testRemoteImageDownloadsOnDemandOnceAndSurvivesOfflineReopen() async throws {
        let scope = scope
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

    private func fixture(responseURL: String? = nil) async throws -> (NoteLibraryStore, ImageDownloadTransport, String) {
        let responseField = responseURL.map { #","url":"\#($0)""# } ?? ""
        let raw = #"{"schema_version":1,"editor_kind":"blocknote","blocks":[{"id":"image","type":"image","props":{"mediaRef":"\#(ref)"\#(responseField)}}]}"#
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
    let searchNote: NoteRemoteSnapshot?
    var downloads = 0
    var isWaiting: Bool { waiting != nil }
    private var failure = false
    private var hold = false
    private var waiting: CheckedContinuation<Void, Never>?
    init(scope: NoteStoreScope, searchNote: NoteRemoteSnapshot? = nil) {
        self.scope = scope
        self.searchNote = searchNote
    }
    func failDownloads() { failure = true }
    func holdDownloads() { hold = true }
    func releaseDownload() { waiting?.resume(); waiting = nil }
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.transient(retryAfter: nil) }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        guard let searchNote, searchNote.assetID == assetID else { throw NoteSyncFailure.notFound }
        try await Task.sleep(nanoseconds: 15_000_000)
        return searchNote
    }
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
