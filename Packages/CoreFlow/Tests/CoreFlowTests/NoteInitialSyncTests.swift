import XCTest
@testable import CoreFlow

@MainActor
final class NoteInitialSyncTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "reader", environmentID: "local")
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRecentPageIsEditableBeforeManifestAndEveryBackfillPageIsPublished() async throws {
        let service = InitialSyncServer(scope: scope)
        let library = NoteLibraryStore(rootURL: root) { _ in service }
        await library.configure(scope: scope, cloudEnabled: true)
        let sync = Task { await library.synchronize() }
        await service.manifestGate.started()

        var visible = Set(library.notes.compactMap(\.serverAssetID))
        XCTAssertEqual(visible, service.recentIDs, "Recent bodies must be on screen while the full manifest is still blocked")
        if let newest = library.notes.first {
            let id = NoteLibraryStore.identifier(newest)
            let opened = try await library.open(identifier: id, scope: scope)
            XCTAssertEqual(opened.body.content, "body 46")
            _ = try await library.save(identifier: id, createID: "", body: OfflineNoteBody(content: "edited during backfill"),
                                       scope: scope, observedBodyRevision: opened.bodyRevision)
        }
        await service.manifestGate.release()
        await service.lastPageGate.started()
        visible = Set(library.notes.compactMap(\.serverAssetID))
        XCTAssertEqual(visible.count, 40, "The first backfill page must be usable before the last request finishes")
        XCTAssertTrue(visible.isSuperset(of: service.recentIDs))
        await service.lastPageGate.release()
        await sync.value
        let batches = await service.batches
        let details = await service.details
        XCTAssertEqual(batches.map(\.count), [20, 7])
        XCTAssertTrue(details.isEmpty, "The batch-capable server must not receive per-note GETs")
        XCTAssertEqual(Set(batches.flatMap { $0 }).count, 27)
        XCTAssertTrue(Set(batches.flatMap { $0 }).isDisjoint(with: service.recentIDs))
        XCTAssertEqual(library.notes.count, 47)
        XCTAssertEqual(library.notes.first { $0.serverAssetID == "note46" }?.body.content, "edited during backfill")
        XCTAssertEqual(library.notes.first { $0.serverAssetID == "note0" }?.desiredLifecycle, .trashed)
        await library.configure(scope: nil, cloudEnabled: false)

        await library.configure(scope: scope, cloudEnabled: false)
        XCTAssertEqual(Set(library.notes.compactMap(\.serverAssetID)).count, 47)
        XCTAssertEqual(library.notes.first { $0.serverAssetID == "note46" }?.body.content, "edited during backfill")
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testInterruptedBackfillResumesFromDiskAndIgnoresLatePageAfterScopeSwitch() async throws {
        let scope = scope
        let service = InitialSyncServer(scope: scope)
        let library = NoteLibraryStore(rootURL: root) { selected in
            selected == scope ? service : InitialSyncServer(scope: selected)
        }
        await library.configure(scope: scope, cloudEnabled: true)
        let first = Task { await library.synchronize() }
        await service.manifestGate.started()
        await service.manifestGate.release()
        await service.lastPageGate.started()
        let before = Set(library.notes.compactMap(\.serverAssetID))
        XCTAssertEqual(before.count, 40)
        await library.configure(scope: NoteStoreScope(actorID: "other", environmentID: "local"), cloudEnabled: false)
        await service.lastPageGate.release()
        await first.value
        XCTAssertTrue(library.notes.isEmpty)
        await library.configure(scope: scope, cloudEnabled: false)
        XCTAssertEqual(Set(library.notes.compactMap(\.serverAssetID)), before)
        await service.clearRequests()
        await library.configure(scope: scope, cloudEnabled: true)
        await library.synchronize()
        let resumedBatches = await service.batches
        let recentRequests = await service.recentRequests
        XCTAssertEqual(recentRequests, 0, "Already downloaded recent bodies must not be fetched again")
        XCTAssertEqual(resumedBatches.map(\.count), [7])
        XCTAssertTrue(Set(resumedBatches.flatMap { $0 }).isDisjoint(with: before))
        XCTAssertEqual(Set(library.notes.compactMap(\.serverAssetID)).count, 47)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testNewPhoneReadsAThousandNotesInBoundedPagesAndDoesNotRefetchThem() async throws {
        let service = InitialSyncServer(scope: scope, count: 1003, holdPages: false)
        let library = NoteLibraryStore(rootURL: root) { _ in service }
        await library.configure(scope: scope, cloudEnabled: true)
        await library.synchronize()
        let recent = await service.recentRequests
        let batches = await service.batches
        let singles = await service.details
        XCTAssertEqual(recent, 1)
        XCTAssertEqual(batches.map(\.count), Array(repeating: 20, count: 49) + [3])
        XCTAssertTrue(singles.isEmpty)
        XCTAssertEqual(library.notes.count, 1003)
        XCTAssertEqual(Set(library.notes.compactMap(\.serverAssetID)).count, 1003)
        await service.clearRequests()
        await library.synchronize()
        let nextBatches = await service.batches
        let nextRecent = await service.recentRequests
        let nextSingles = await service.details
        XCTAssertEqual(nextRecent, 0)
        XCTAssertTrue(nextBatches.isEmpty && nextSingles.isEmpty)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testInconsistentBatchIsRejectedWithoutDroppingTheFirstPage() async throws {
        let service = InitialSyncServer(scope: scope, holdPages: false)
        await service.setMalformedPage(true)
        let library = NoteLibraryStore(rootURL: root) { _ in service }
        await library.configure(scope: scope, cloudEnabled: true)
        await library.synchronize()
        XCTAssertEqual(Set(library.notes.compactMap(\.serverAssetID)), service.recentIDs)
        XCTAssertEqual(library.status, .notReady)
        await service.setMalformedPage(false)
        await library.synchronize()
        XCTAssertEqual(library.notes.count, 47)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testServerWithoutPageRouteUsesOriginalOwnerDetails() async throws {
        let service = InitialSyncServer(scope: scope, holdPages: false, hasPageRoute: false)
        let library = NoteLibraryStore(rootURL: root) { _ in service }
        await library.configure(scope: scope, cloudEnabled: true)
        await library.synchronize()
        let details = await service.details
        let recent = await service.recentRequests
        XCTAssertEqual(recent, 1)
        XCTAssertEqual(details.count, 47)
        XCTAssertEqual(Set(library.notes.compactMap(\.serverAssetID)).count, 47)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testOneFailedBackfillPageCanBeRetriedWithoutStarvingOlderPages() async throws {
        let service = InitialSyncServer(scope: scope, holdPages: false)
        await service.failFirstBackfill()
        let library = NoteLibraryStore(rootURL: root) { _ in service }
        await library.configure(scope: scope, cloudEnabled: true)
        await library.synchronize()
        XCTAssertEqual(library.notes.count, 27, "The following seven bodies should still reach the device")
        XCTAssertEqual(library.status, .waitingForNetwork)
        await service.clearRequests()
        await library.synchronize(forceRetry: true)
        let retried = await service.batches
        XCTAssertEqual(retried.map(\.count), [20])
        XCTAssertEqual(library.notes.count, 47)
        await library.configure(scope: nil, cloudEnabled: false)
    }
}

private actor InitialSyncServer: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    nonisolated let recentIDs: Set<String>
    let manifestGate = NoteSyncTestGate()
    let lastPageGate = NoteSyncTestGate()
    private let snapshots: [NoteRemoteSnapshot]
    private let holdPages: Bool
    private let hasPageRoute: Bool
    private var malformedPage = false
    private var shouldFail = false
    private var manifestCalls = 0
    private var didGateLastPage = false
    private(set) var batches: [[String]] = []
    private(set) var recentRequests = 0
    private(set) var details: [String] = []

    init(scope: NoteStoreScope, count: Int = 47, holdPages: Bool = true, hasPageRoute: Bool = true) {
        self.scope = scope
        self.holdPages = holdPages
        self.hasPageRoute = hasPageRoute
        self.recentIDs = Set(((count - 20)..<count).map { "note\($0)" })
        snapshots = (0..<count).map { index in
            NoteRemoteSnapshot(assetID: "note\(index)", syncToken: "v1-\(index)",
                               body: OfflineNoteBody(content: "body \(index)"),
                               lifecycle: index < 3 ? .trashed : .active, isPublic: false,
                               updatedAt: Date(timeIntervalSince1970: Double(index)))
        }
    }

    func readPage(assetIDs: [String]?) async throws -> [NoteRemoteSnapshot]? {
        guard let assetIDs else {
            recentRequests += 1
            if !hasPageRoute { return nil }
            return Array(snapshots.suffix(20).reversed())
        }
        batches.append(assetIDs)
        if shouldFail {
            shouldFail = false
            throw NoteSyncFailure.transient(retryAfter: nil)
        }
        if holdPages && batches.count == 2 { await gateLastPageOnce() }
        if malformedPage { return [snapshots[0], snapshots[0]] }
        return snapshots.filter { assetIDs.contains($0.assetID) }
    }

    func manifest() async throws -> NoteSyncManifest {
        manifestCalls += 1
        if holdPages && manifestCalls == 1 { await manifestGate.wait() }
        return NoteSyncManifest(protocolVersion: 3, complete: true, notes: snapshots.map {
            .init(assetID: $0.assetID, syncToken: $0.syncToken, lifecycle: $0.lifecycle)
        })
    }

    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        details.append(assetID)
        if holdPages && details.count == 41 { await gateLastPageOnce() }
        return try XCTUnwrap(snapshots.first { $0.assetID == assetID })
    }

    private func gateLastPageOnce() async {
        guard !didGateLastPage else { return }
        didGateLastPage = true
        await lastPageGate.wait()
    }

    func clearRequests() {
        batches = []
        details = []
        recentRequests = 0
    }

    func setMalformedPage(_ value: Bool) { malformedPage = value }
    func failFirstBackfill() { shouldFail = true }

    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.transient(retryAfter: nil) }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.validation }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notFound }
}
