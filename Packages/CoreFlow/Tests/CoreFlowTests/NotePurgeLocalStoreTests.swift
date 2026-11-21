import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NotePurgeLocalStoreTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "actor", environmentID: "local")
    private var root: URL!
    override func setUp() async throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func seed(_ store: NoteLocalStore) async throws -> OfflineNote {
        let remote = NoteRemoteSnapshot(assetID: "asset", syncToken: "trash_base", body: OfflineNoteBody(content: "preserved"), lifecycle: .trashed, isPublic: false)
        let inserted = try await store.applyRemote(remote, localID: nil, expectedGeneration: nil)
        return try XCTUnwrap(inserted)
    }

    private func receipt(_ attempt: NotePurgeWriteAttempt, requestID: String? = nil, assetID: String? = nil) -> NotePurgeWriteReceipt {
        NotePurgeWriteReceipt(assetID: assetID ?? attempt.assetID, requestID: requestID ?? attempt.requestID,
            state: "ERASED", activityID: "activity", actionLogID: "action_log", certificateID: "certificate", cleanupState: .pending)
    }

    func testReopenRetainsOriginalCommandAndRemovesItWithTheLocalNoteAtomically() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        try receipt(attempt).validate(for: attempt)
        try await store.close()
        // Simulate termination after server acknowledgement, before local commit.
        let reopened = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let recovered = try await reopened.beginPurge(localID: note.localID, baseSyncToken: "different_display")
        XCTAssertEqual(recovered, attempt)
        try await reopened.confirmPurge(attempt, receipt: receipt(attempt))
        let missing = try await reopened.note(localID: note.localID)
        XCTAssertNil(missing)
        try await reopened.close()
        let final = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let notes = try await final.notes()
        XCTAssertTrue(notes.isEmpty)
        try await final.close()
    }

    func testPendingPurgePreventsRestoreEditAndRemoteOverwriteButRetainsBody() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        do { _ = try await store.setLifecycle(localID: note.localID, lifecycle: .active); XCTFail("Restored during unknown erase") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .pendingOperationExists) }
        do { _ = try await store.saveBody(localID: note.localID, body: OfflineNoteBody(content: "overwrite")); XCTFail("Edited during erase") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .pendingOperationExists) }
        let remote = NoteRemoteSnapshot(assetID: "asset", syncToken: "new", body: OfflineNoteBody(content: "other"), lifecycle: .active, isPublic: true)
        let applied = try await store.applyRemote(remote, localID: note.localID, expectedGeneration: attempt.localGeneration)
        XCTAssertNil(applied)
        let retained = try await store.note(localID: note.localID)
        XCTAssertEqual(retained?.body.content, "preserved")
        XCTAssertEqual(retained?.pendingPurge, attempt)
        try await store.close()
    }

    func testWrongReceiptAndOldAckCannotClearCurrentOrReplacementNote() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        for invalid in [receipt(attempt, requestID: "wrong"), receipt(attempt, assetID: "other")] {
            do { try await store.confirmPurge(attempt, receipt: invalid); XCTFail("Wrong receipt accepted") } catch {}
        }
        try await store.rejectPurge(attempt, status: 409, reason: "stale_version")
        let next = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        XCTAssertNotEqual(attempt.requestID, next.requestID)
        do { try await store.confirmPurge(attempt, receipt: receipt(attempt)); XCTFail("Old receipt erased replacement") } catch {}
        let retained = try await store.note(localID: note.localID)
        XCTAssertEqual(retained?.pendingPurge, next)
        try await store.close()
    }

    func testOnlyAuthoritativePrecommitRejectionReleasesIntent() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        for (status, reason) in [(503, "note_action_outcome_unknown"), (401, "unauthorized"),
                                 (409, "idempotency_conflict"), (404, "not_found"), (500, "stale_version")] {
            try await store.rejectPurge(attempt, status: status, reason: reason)
            let retained = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
            XCTAssertEqual(retained, attempt)
        }
        try await store.rejectPurge(attempt, status: 409, reason: "stale_version")
        _ = try await store.setLifecycle(localID: note.localID, lifecycle: .active)
        try await store.close()
    }

    func testMissingDisplayedBaselineUnsyncedBodyAndOtherAccountCannotErase() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        for base in ["", "new_base"] {
            do { _ = try await store.beginPurge(localID: note.localID, baseSyncToken: base); XCTFail("Wrong displayed baseline accepted") } catch {}
        }
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        let other = try await NoteLocalStore.open(rootURL: root, scope: NoteStoreScope(actorID: "other", environmentID: "local"))
        do { try await other.confirmPurge(attempt, receipt: receipt(attempt)); XCTFail("Other account accepted") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidScope) }
        try await other.close()
        try await store.rejectPurge(attempt, status: 409, reason: "stale_version")
        _ = try await store.saveBody(localID: note.localID, body: OfflineNoteBody(content: "unsent"))
        do { _ = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base"); XCTFail("Unsent body erased") } catch {}
        try await store.close()
    }

    func testSyncStartedBeforePurgeDoesNotMarkItsUnknownOutcomeUnavailable() async throws {
        try await checkManifestOverlap(completed: false)
    }

    func testCompletedPurgeDoesNotAbortAnEarlierManifest() async throws {
        try await checkManifestOverlap(completed: true)
    }

    private func checkManifestOverlap(completed: Bool) async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        let started = expectation(description: "manifest read")
        let service = PurgeManifestTransport(scope: scope, onStart: { started.fulfill() })
        let sync = try NoteSyncCoordinator(store: store, service: service)
        await sync.resume()
        let work = Task { await sync.synchronize(forceRetry: true) }
        await fulfillment(of: [started], timeout: 2)
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        if completed { try await store.confirmPurge(attempt, receipt: receipt(attempt)) }
        // The server already erased this note, but the DELETE response was lost.
        await service.finish()
        await work.value
        let retained = try await store.note(localID: note.localID)
        XCTAssertEqual(retained?.pendingPurge, completed ? nil : attempt)
        XCTAssertNil(retained?.syncIssue)
        let state = await sync.status
        XCTAssertEqual(state, .idle)
        let writes = await service.writes
        XCTAssertEqual(writes, 0)
        await sync.suspend(); try await store.close()
    }

    func testDelayedDetailAbsenceDoesNotFailSyncWhenPurgeOwnsOrRemovedTheNote() async throws {
        try await checkDetailOverlap(succeeds: false)
    }

    func testDelayedDetailSuccessCannotReviveOrFailACompletedPurge() async throws {
        try await checkDetailOverlap(succeeds: true)
    }

    private func checkDetailOverlap(succeeds: Bool) async throws {
        for completed in [false, true] {
            let store = try await NoteLocalStore.open(rootURL: root.appendingPathComponent(UUID().uuidString), scope: scope)
            let note = try await seed(store)
            let started = expectation(description: "detail read")
            let service = PurgeManifestTransport(scope: scope, onStart: { started.fulfill() }, delayDetail: true, detailSucceeds: succeeds)
            let sync = try NoteSyncCoordinator(store: store, service: service)
            await sync.resume()
            let work = Task { await sync.synchronize(forceRetry: true) }
            await fulfillment(of: [started], timeout: 2)
            let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
            if completed { try await store.confirmPurge(attempt, receipt: receipt(attempt)) }
            await service.finishDetail()
            await work.value
            let state = await sync.status
            XCTAssertEqual(state, .idle)
            let retained = try await store.note(localID: note.localID)
            XCTAssertEqual(retained?.pendingPurge, completed ? nil : attempt)
            XCTAssertNil(retained?.syncIssue)
            await sync.suspend(); try await store.close()
        }
    }

    func testAuthoritativeAbsenceRemovesOnlyItsUnchangedUserConfirmedLocalCopy() async throws {
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await seed(store)
        let attempt = try await store.beginPurge(localID: note.localID, baseSyncToken: "trash_base")
        try await store.rejectPurge(attempt, status: 404, reason: "purge_target_absent")
        let missing = try await store.note(localID: note.localID)
        XCTAssertNil(missing)
        // A second note using the same server identity is not this local intent.
        let replacement = try await seed(store)
        try await store.rejectPurge(attempt, status: 404, reason: "purge_target_absent")
        let retained = try await store.note(localID: replacement.localID)
        XCTAssertEqual(retained, replacement)
        try await store.close()
    }
}

private actor PurgeManifestTransport: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    let onStart: @Sendable () -> Void
    let delayDetail: Bool
    let detailSucceeds: Bool
    private var continuation: CheckedContinuation<NoteSyncManifest, Never>?
    private var detailContinuation: CheckedContinuation<Void, Never>?
    private(set) var writes = 0
    init(scope: NoteStoreScope, onStart: @escaping @Sendable () -> Void, delayDetail: Bool = false, detailSucceeds: Bool = false) {
        self.scope = scope; self.onStart = onStart; self.delayDetail = delayDetail; self.detailSucceeds = detailSucceeds
    }
    func manifest() async throws -> NoteSyncManifest {
        if delayDetail { return NoteSyncManifest(protocolVersion: 3, complete: true, notes: [.init(assetID: "asset", syncToken: "different", lifecycle: .trashed)]) }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation; onStart()
        }
    }
    func finish() { continuation?.resume(returning: NoteSyncManifest(protocolVersion: 3, complete: true, notes: [])); continuation = nil }
    func finishDetail() { detailContinuation?.resume(); detailContinuation = nil }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        if delayDetail {
            await withCheckedContinuation { continuation in
                detailContinuation = continuation; onStart()
            }
        }
        if detailSucceeds { return NoteRemoteSnapshot(assetID: assetID, syncToken: "different", body: OfflineNoteBody(content: "old response"), lifecycle: .trashed, isPublic: false) }
        throw NoteSyncFailure.notFound
    }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt { writes += 1; throw NoteSyncFailure.transient(retryAfter: nil) }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.transient(retryAfter: nil) }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notFound }
}
