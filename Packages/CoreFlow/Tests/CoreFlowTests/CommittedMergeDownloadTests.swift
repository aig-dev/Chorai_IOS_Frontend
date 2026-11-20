import XCTest
@testable import CoreFlow

@MainActor
final class CommittedMergeDownloadTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "actor_1", environmentID: "local")
    private let assetID = "ast_mgv1_" + String(repeating: "a", count: 52)
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testAcknowledgedMergeDownloadsEveryImageAfterRestartWithoutOpeningTheNote() async throws {
        let server = MergeNoteServer(scope: scope)
        let library = NoteLibraryStore(rootURL: root) { _ in server }
        await library.configure(scope: scope, cloudEnabled: false)

        // Restore the exact boundary between receiving the cloud commit and returning to Home.
        let jobID = "job-committed"
        var record = makeMergeTaskRecord(jobID: jobID, status: .committedCard)
        record.snapshot.committedAssetID = assetID
        var collection = MergeTaskCollection.empty(actorID: scope.actorID)
        collection.tasks[jobID] = record
        let tasks = InMemoryMergeTaskCollectionStore(collection: collection)
        let coordinator = MergeTaskCoordinator(service: MockCoreMergeService(), persistence: tasks, queueCommittedNote: { actorID, assetID in
            try library.queueCommittedNote(assetID: assetID, scope: NoteStoreScope(actorID: actorID, environmentID: self.scope.environmentID))
        })
        coordinator.activate(actorID: scope.actorID)
        await waitForMergeStore { coordinator.committedCardIntent?.assetID == self.assetID }
        coordinator.acknowledgeCommittedCardIntent(jobID: jobID)
        XCTAssertNil(tasks.collection(actorID: scope.actorID).tasks[jobID])
        XCTAssertTrue(library.notes.isEmpty)
        await library.configure(scope: nil, cloudEnabled: false)

        let reopened = NoteLibraryStore(rootURL: root) { _ in server }
        await reopened.configure(scope: scope, cloudEnabled: true)
        await waitForMergeStore { reopened.notes.first?.attachments.count == 2 }
        await reopened.configure(scope: nil, cloudEnabled: false)

        let offline = NoteLibraryStore(rootURL: root) { _ in server }
        await offline.configure(scope: scope, cloudEnabled: false)
        let note = try await offline.open(identifier: assetID, scope: scope)
        XCTAssertEqual(note.body.content, "Merged text")
        XCTAssertTrue(note.isSynchronized)
        let urls = try await offline.imageDisplayURLs(identifier: assetID, scope: scope)
        for ref in server.refs {
            let url = try XCTUnwrap(urls[ref].flatMap(URL.init(string:)))
            let image = try await offline.imagePreview(url, identifier: assetID, scope: scope)
            XCTAssertEqual(image.data, Data(ref.utf8))
        }
        let reads = await server.downloads
        XCTAssertEqual(reads.sorted(), server.refs.sorted())
        await offline.configure(scope: nil, cloudEnabled: false)
    }

    func testAnUnavailableImageDoesNotBlockOthersAndReconnectRetriesOnlyTheMissingBytes() async throws {
        let server = MergeNoteServer(scope: scope)
        await server.failFirstImage()
        let library = NoteLibraryStore(rootURL: root) { _ in server }
        await library.configure(scope: scope, cloudEnabled: true)
        try library.queueCommittedNote(assetID: assetID, scope: scope)
        try library.queueCommittedNote(assetID: assetID, scope: scope)
        await waitForMergeStore { library.notes.first?.attachments.compactMap(\.mediaRef) == [server.refs[1]] }

        await library.configure(scope: scope, cloudEnabled: false)
        let before = try await library.open(identifier: assetID)
        let edit = OfflineNoteBody(content: "My offline edit", contentJSON: before.body.contentJSON)
        _ = try await library.save(identifier: assetID, createID: "", body: edit, scope: scope)
        await library.configure(scope: scope, cloudEnabled: true)
        await waitForMergeStore { library.notes.first?.attachments.count == 2 }

        let recovered = try await library.open(identifier: assetID)
        XCTAssertEqual(recovered.body, edit)
        XCTAssertTrue(recovered.hasUnacknowledgedBody)
        let requests = await server.downloads
        XCTAssertEqual(requests, [server.refs[0], server.refs[1], server.refs[0]])
        let details = await server.details
        XCTAssertEqual(details, [assetID])
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testServerRetryAfterSurvivesReconnectAndDoesNotBlockTheNextCommit() async throws {
        let server = MergeNoteServer(scope: scope)
        await server.failFirstImage(retryAfter: 120)
        let library = NoteLibraryStore(rootURL: root) { _ in server }
        await library.configure(scope: scope, cloudEnabled: true)
        try library.queueCommittedNote(assetID: assetID, scope: scope)
        await waitForMergeCondition(message: "The download should receive the advertised delay") { await server.downloads == [server.refs[0]] }
        // Let the rejected request settle before reconnecting.
        try library.queueCommittedNote(assetID: "another-merge", scope: scope)
        await waitForMergeStore { library.notes.contains { $0.serverAssetID == "another-merge" && $0.attachments.count == 2 } }

        await library.configure(scope: scope, cloudEnabled: false)
        await library.configure(scope: scope, cloudEnabled: true)
        try library.queueCommittedNote(assetID: "third-merge", scope: scope)
        await waitForMergeStore { library.notes.contains { $0.serverAssetID == "third-merge" && $0.attachments.count == 2 } }
        let waiting = try await library.open(identifier: assetID)
        XCTAssertTrue(waiting.attachments.isEmpty, "A reconnect must respect the first note's Retry-After")
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testSwitchingAccountsDuringBodyReadCannotConsumeAnotherAccountsReceipt() async throws {
        let otherScope = NoteStoreScope(actorID: "different-actor", environmentID: scope.environmentID)
        let server = MergeNoteServer(scope: scope)
        let other = MergeNoteServer(scope: otherScope)
        await server.holdNextDetail()
        let library = NoteLibraryStore(rootURL: root) { $0 == otherScope ? other : server }
        await library.configure(scope: scope, cloudEnabled: true)
        try library.queueCommittedNote(assetID: assetID, scope: scope)
        await waitForMergeCondition(message: "The original account should request its committed body") { await server.waitingForDetail }
        await library.configure(scope: otherScope, cloudEnabled: true)
        await server.releaseDetail()
        XCTAssertTrue(library.notes.isEmpty)
        await library.configure(scope: scope, cloudEnabled: true)
        await waitForMergeStore { library.notes.first?.attachments.count == 2 }
        XCTAssertEqual(library.notes.map(\.serverAssetID), [assetID])
        let otherReads = await other.details
        let otherImages = await other.downloads
        XCTAssertTrue(otherReads.isEmpty && otherImages.isEmpty)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testReceiptSurvivesFailedLocalHandoffAndRetriesWithoutAnotherServerCommit() async throws {
        let jobID = "completed"
        var snapshot = makeMergeSnapshot(jobID: jobID, status: .committedCard)
        snapshot.committedAssetID = assetID
        let persistence = InMemoryMergeSessionPersistence()
        persistence.save(snapshot)
        let service = MockCoreMergeService()
        let handoff = CommitHandoffState()
        let store = MergeSessionStore(actorID: scope.actorID, anchor: snapshot.createRequest.sources[0],
            service: service, persistence: persistence, queueCommittedNote: { actorID, id in
                XCTAssertEqual(actorID, self.scope.actorID)
                guard handoff.canWrite else { throw CocoaError(.fileWriteOutOfSpace) }
                handoff.accepted.append(id)
            })
        store.start()
        guard case .paused = store.phase else { return XCTFail("A failed local handoff must retain the receipt") }
        store.acknowledgeCompletion()
        XCTAssertEqual(persistence.snapshot(actorID: scope.actorID)?.committedAssetID, assetID)
        handoff.canWrite = true
        store.retry()
        XCTAssertEqual(store.phase, .completed(assetID: assetID))
        XCTAssertEqual(handoff.accepted, [assetID])
        let commits = await service.commitCalls
        XCTAssertTrue(commits.isEmpty)
    }
}

@MainActor
private final class CommitHandoffState {
    var canWrite = false
    var accepted: [String] = []
}

private actor MergeNoteServer: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    nonisolated let refs = ["b", "c"].map { "med_mgv1_" + String(repeating: $0, count: 52) }
    private(set) var downloads: [String] = []
    private(set) var details: [String] = []
    private var firstFailure: NoteSyncFailure?
    private var holdDetail = false
    private var held: CheckedContinuation<Void, Never>?
    var waitingForDetail: Bool { held != nil }
    func holdNextDetail() { holdDetail = true }
    func releaseDetail() { held?.resume(); held = nil }
    func failFirstImage(retryAfter: TimeInterval? = nil) { firstFailure = .transient(retryAfter: retryAfter) }

    init(scope: NoteStoreScope) { self.scope = scope }

    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.notReady }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        details.append(assetID)
        if holdDetail {
            holdDetail = false
            await withCheckedContinuation { held = $0 }
        }
        let raw = #"{"schema_version":1,"editor_kind":"blocknote","blocks":[{"type":"paragraph","content":[{"type":"text","text":"Merged text"}],"children":[{"type":"image","props":{"mediaRef":"\#(refs[1])"}}]},{"type":"image","props":{"mediaRef":"\#(refs[0])"}},{"type":"image","props":{"mediaRef":"\#(refs[0])"}}]}"#
        return NoteRemoteSnapshot(assetID: assetID, syncToken: "version-1", body: OfflineNoteBody(content: "Merged text", contentJSON: raw), lifecycle: .active, isPublic: false)
    }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment {
        downloads.append(mediaRef)
        if let firstFailure, mediaRef == refs[0] {
            self.firstFailure = nil
            throw firstFailure
        }
        return NoteSyncDownloadedAttachment(data: Data(mediaRef.utf8), filename: "merged.png", mimeType: "image/png")
    }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt {
        XCTFail("Downloading a Merge attempted a cloud write")
        throw NoteSyncFailure.invalidResponse
    }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt {
        XCTFail("Downloading a Merge attempted an upload")
        throw NoteSyncFailure.invalidResponse
    }
}
