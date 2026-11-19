import XCTest
@testable import CoreFlow
@testable import ArcNote

@MainActor
final class HomeCardProjectionTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "alice", environmentID: "local")

    func testThousandNotesAndBatchChangesMatchFullSortOffMain() async throws {
        let probe = ProjectionThreadProbe()
        let worker = HomeCardProjectionWorker(probe: { probe.record() })
        for sortBy in ["created_at", "updated_at"] {
            for order in ["asc", "desc"] {
                var notes = (0..<1_000).map(Self.note)
                let initial = await worker.reset(notes: notes, scope: scope, sortBy: sortBy, sortOrder: order)
                XCTAssertEqual(initial.map(\.id), expected(notes, sortBy: sortBy, order: order))
                var changed = Array(notes.prefix(200))
                for index in changed.indices {
                    changed[index].updatedAt = Date(timeIntervalSince1970: Double(2_000 + index))
                    changed[index].isPinned = index % 3 == 0
                    changed[index].body = .init(content: "changed-\(index)")
                }
                changed[3].desiredLifecycle = .trashed
                let removed: Set<String> = [notes[999].localID]
                let result = await worker.update(changed: changed, removed: removed)
                notes.replaceSubrange(0..<200, with: changed)
                notes.removeAll { removed.contains($0.localID) }
                XCTAssertEqual(result.map(\.id), expected(notes, sortBy: sortBy, order: order))
                XCTAssertEqual(result.first { $0.id == "local-note:0000" }?.content, "changed-0")
                XCTAssertTrue(result.allSatisfy { $0.localPreviewIdentity?.scope == scope })
            }
        }
        XCTAssertFalse(probe.values.isEmpty)
        XCTAssertTrue(probe.values.allSatisfy { !$0 })
    }

    func testManagerCoalescesUpdatesAndDoesNotResurrectRemovedNote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NoteLibraryStore(rootURL: root, service: { HomeOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        _ = try await library.save(identifier: nil, createID: "one", body: .init(content: "old"), scope: scope)
        let gate = ProjectionGate()
        let manager = HomeCardsManager(projectionWorker: HomeCardProjectionWorker(beforeWork: { await gate.waitOnce() }), library: library)
        manager.loadUserCards()
        await gate.waitUntilEntered()
        _ = try await library.save(identifier: "local-note:one", createID: "one", body: .init(content: "new"), scope: scope)
        _ = try await library.save(identifier: nil, createID: "two", body: .init(content: "latest"), scope: scope)
        try await library.setLifecycle(identifier: "local-note:one", lifecycle: .trashed, scope: scope)
        await gate.open()
        await manager.waitForLocalProjection()
        XCTAssertEqual(manager.cards.map(\.id), ["local-note:two"])
        XCTAssertEqual(manager.cards.first?.content, "latest")
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testScopeAndSortSwitchRejectSuspendedProjection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NoteLibraryStore(rootURL: root, service: { HomeOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        _ = try await library.save(identifier: nil, createID: "alice", body: .init(content: "private"), scope: scope)
        let gate = ProjectionGate()
        let manager = HomeCardsManager(projectionWorker: HomeCardProjectionWorker(beforeWork: { await gate.waitOnce() }), library: library)
        manager.loadUserCards()
        await gate.waitUntilEntered()
        let bob = NoteStoreScope(actorID: "bob", environmentID: "local")
        await library.configure(scope: bob, cloudEnabled: false)
        _ = try await library.save(identifier: nil, createID: "first", body: .init(content: "first"), scope: bob)
        _ = try await library.save(identifier: nil, createID: "last", body: .init(content: "last"), scope: bob)
        manager.loadUserCards(sortBy: "created_at", sortOrder: "asc")
        XCTAssertTrue(manager.cards.isEmpty)
        await gate.open()
        await manager.waitForLocalProjection()
        XCTAssertEqual(manager.cards.map(\.content), ["first", "last"])
        XCTAssertTrue(manager.cards.allSatisfy { $0.ownerActorId == "bob" })
        await library.configure(scope: nil, cloudEnabled: false)
        XCTAssertTrue(manager.cards.isEmpty)
        await manager.waitForLocalProjection()
    }

    func testDeniedProfileEntryCannotPublishSuspendedOwnedProjection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NoteLibraryStore(rootURL: root, service: { HomeOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        _ = try await library.save(identifier: nil, createID: "private", body: .init(content: "private"), scope: scope)
        let gate = ProjectionGate()
        let manager = HomeCardsManager(projectionWorker: HomeCardProjectionWorker(beforeWork: { await gate.waitOnce() }),
                                       library: library, readSession: { nil })
        manager.loadUserCards()
        await gate.waitUntilEntered()
        manager.loadPublicProfileCards(actorId: "bob", refresh: true)
        await gate.open()
        await manager.waitForLocalProjection()
        XCTAssertTrue(manager.cards.isEmpty)
        XCTAssertFalse(manager.isLoading)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testInitialLoadingWaitsForFirstProjectionAfterOfflineSync() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NoteLibraryStore(rootURL: root, service: { HomeOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        _ = try await library.save(identifier: nil, createID: "one", body: .init(content: "saved"), scope: scope)
        let gate = ProjectionGate()
        let manager = HomeCardsManager(projectionWorker: HomeCardProjectionWorker(beforeWork: { await gate.waitOnce() }), library: library)
        manager.loadUserCards()
        await gate.waitUntilEntered()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertTrue(manager.cards.isEmpty)
        XCTAssertTrue(manager.isLoading, "A populated library must not render its empty state during initial projection")
        await gate.open()
        await manager.waitForLocalProjection()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(manager.cards.map(\.content), ["saved"])
        XCTAssertFalse(manager.isLoading)
        await library.configure(scope: nil, cloudEnabled: false)
    }

    func testThousandNoteProjectionMeasurements() async {
        let notes = (0..<1_000).map(Self.note)
        let changed = (0..<200).map { index -> OfflineNote in
            var note = Self.note(index)
            note.updatedAt = Date(timeIntervalSince1970: Double(2_000 + index))
            return note
        }
        let legacy = LegacyHomeProjection()
        let worker = HomeCardProjectionWorker()
        let manager = HomeCardsManager()
        let subscription = manager.$cards.sink { _ in }
        defer { subscription.cancel() }
        var publication: [Double] = []
        var oldReset: [Double] = [], oldUpdate: [Double] = [], reset: [Double] = [], update: [Double] = []
        for _ in 0..<20 {
            var start = ProcessInfo.processInfo.systemUptime
            legacy.presentLocalNotes(notes, scope: scope)
            oldReset.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            start = ProcessInfo.processInfo.systemUptime
            legacy.updateLocalCards(changed, removed: [], scope: scope)
            oldUpdate.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            start = ProcessInfo.processInfo.systemUptime
            _ = await worker.reset(notes: notes, scope: scope, sortBy: "updated_at", sortOrder: "desc")
            reset.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            start = ProcessInfo.processInfo.systemUptime
            let result = await worker.update(changed: changed, removed: [])
            update.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(result.map(\.id), legacy.cards.map(\.id))
            start = ProcessInfo.processInfo.systemUptime
            manager.cards = result
            publication.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
        ExecutionFixtures.report("home_1000_main_publication_no_layout", samples: publication)
        ExecutionFixtures.report("home_1000_reset_before_main", samples: oldReset)
        ExecutionFixtures.report("home_1000_update_200_before_main", samples: oldUpdate)
        ExecutionFixtures.report("home_1000_reset_after_worker_roundtrip", samples: reset)
        ExecutionFixtures.report("home_1000_update_200_after_worker_roundtrip", samples: update)
    }

    static func note(_ index: Int) -> OfflineNote {
        var note = OfflineNote(localID: String(format: "%04d", index), body: .init(content: "note-\(index)"), now: Date(timeIntervalSince1970: Double(index / 2)))
        note.updatedAt = Date(timeIntervalSince1970: Double(1_000 - index / 2))
        note.isPinned = index % 7 == 0
        return note
    }

    private func expected(_ notes: [OfflineNote], sortBy: String, order: String) -> [String] {
        notes.filter { $0.desiredLifecycle == .active }.sorted {
            let ap = $0.isPinned ?? false, bp = $1.isPinned ?? false
            if ap != bp { return ap }
            let a = sortBy == "created_at" ? $0.createdAt : $0.updatedAt
            let b = sortBy == "created_at" ? $1.createdAt : $1.updatedAt
            if a == b { return $0.localID < $1.localID }
            return order == "asc" ? a < b : a > b
        }.map(NoteLibraryStore.identifier)
    }
}

private final class ProjectionThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [Bool] = []
    func record() { lock.lock(); defer { lock.unlock() }; threads.append(Thread.isMainThread) }
    var values: [Bool] { lock.lock(); defer { lock.unlock() }; return threads }
}

private actor ProjectionGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func waitOnce() async {
        guard !entered else { return }
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async { while !entered { await Task.yield() } }
    func open() { continuation?.resume(); continuation = nil }
}

struct HomeOfflineTransport: NoteSyncServing {
    let scope: NoteStoreScope
    func manifest() async throws -> NoteSyncManifest { throw NoteSyncFailure.notReady }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot { throw NoteSyncFailure.notReady }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { throw NoteSyncFailure.notReady }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}

// Exact pre-change projection algorithm, retained only to compare synthetic fixture cost.
@MainActor
private final class LegacyHomeProjection {
    var cards: [UserCard] = []
    var currentSortBy: String? = "updated_at"
    var currentSortOrder: String? = "desc"
    var localSortDates: [String: Date] = [:]
    let localDateFormatter = ISO8601DateFormatter()
    func presentLocalNotes(_ notes: [OfflineNote], scope: NoteStoreScope?) {
        guard let scope else { cards = []; localSortDates.removeAll(); return }
        localSortDates.removeAll(keepingCapacity: true)
        cards = notes.filter { $0.desiredLifecycle == .active }.map { localCard($0, scope: scope) }.sorted(by: precedes)
    }

    func updateLocalCards(_ changed: [OfflineNote], removed: Set<String>, scope: NoteStoreScope?) {
        guard let scope else { cards = []; localSortDates.removeAll(); return }
        var result = cards
        if !removed.isEmpty {
            let ids = Set(removed.map { "local-note:" + $0 })
            result.removeAll { ids.contains($0.id) }
            for id in ids { localSortDates[id] = nil }
        }
        for note in changed {
            let id = NoteLibraryStore.identifier(note)
            if let old = result.firstIndex(where: { $0.id == id }) { result.remove(at: old) }
            guard note.desiredLifecycle == .active else { localSortDates[id] = nil; continue }
            let card = localCard(note, scope: scope)
            let index = result.firstIndex { precedes(card, $0) } ?? result.endIndex
            result.insert(card, at: index)
        }
        cards = result
    }

    func localCard(_ note: OfflineNote, scope: NoteStoreScope) -> UserCard {
        let id = NoteLibraryStore.identifier(note)
        localSortDates[id] = currentSortBy == "created_at" ? note.createdAt : note.updatedAt
        return UserCard(id: id, title: note.body.title, content: note.body.content,
            contentJSON: note.body.contentJSON, backgroundMediaRef: note.backgroundMediaRef, contentHash: "",
            isPublic: note.isPublic, tags: note.body.tags, createdAt: localDateFormatter.string(from: note.createdAt),
            updatedAt: localDateFormatter.string(from: note.updatedAt), likeCount: 0, commentCount: nil, isLiked: false,
            isPinned: note.isPinned ?? false, pinnedAt: nil, isFavorited: nil, favoriteCount: nil, rate: 0,
            ownerActorId: scope.actorID, isOwner: true,
            localPreviewIdentity: .init(scope: scope, bodyRevision: note.bodyRevision))
    }

    func precedes(_ lhs: UserCard, _ rhs: UserCard) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        let a = localSortDates[lhs.id] ?? .distantPast
        let b = localSortDates[rhs.id] ?? .distantPast
        if a == b { return lhs.id < rhs.id }
        return currentSortOrder == "asc" ? a < b : a > b
    }

}
