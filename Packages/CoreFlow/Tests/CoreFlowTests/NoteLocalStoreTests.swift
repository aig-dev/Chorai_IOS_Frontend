import CoreData
import Foundation
import XCTest
@testable import CoreFlow

final class NoteLocalStoreTests: XCTestCase {
    func testRemoteDownloadAndConflictAdoptionUseAuthoredTimesNotFetchTimes() async throws {
        let store = try await open()
        let createdAt = Date(timeIntervalSince1970: 1000)
        let updatedAt = Date(timeIntervalSince1970: 2000)
        let remote = NoteRemoteSnapshot(assetID: "remote", syncToken: "v1", body: body("cloud"), lifecycle: .active,
            isPublic: false, createdAt: createdAt, updatedAt: updatedAt)
        let imported = try unwrap(try await store.applyRemote(remote, localID: nil, expectedGeneration: nil))
        XCTAssertEqual(imported.createdAt, createdAt); XCTAssertEqual(imported.updatedAt, updatedAt)
        let edited = try await store.saveBody(localID: imported.localID, body: body("local"))
        let later = NoteRemoteSnapshot(assetID: "remote", syncToken: "v2", body: body("later cloud"), lifecycle: .active,
            isPublic: false, createdAt: createdAt, updatedAt: Date(timeIntervalSince1970: 3000))
        _ = try await store.applyRemote(later, localID: imported.localID, expectedGeneration: edited.generation)
        let adopted = try await store.useRemoteVersion(localID: imported.localID)
        XCTAssertEqual(adopted.createdAt, createdAt)
        XCTAssertEqual(adopted.updatedAt, later.updatedAt)
        try await store.close()
        let reopened = try await open()
        let saved = try unwrap(try await reopened.note(localID: imported.localID))
        XCTAssertEqual(saved.createdAt, createdAt); XCTAssertEqual(saved.updatedAt, later.updatedAt)
        try await reopened.close()
    }

    private var root: URL!
    private let scope = NoteStoreScope(actorID: "actor-a", environmentID: "local")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    // Break caught: returning a successful save before committing the persistent store.
    func testCreateAndEditSurviveClosingAndReopeningDiskStoreWithoutChangingJSON() async throws {
        let store = try await open()
        let raw = #"{ "blocks": [{"id":"a","type":"future","props":{"opaque":[1,2]}}] }"#
        let first = try await store.create(body: body("first"), localID: "local-note")
        let saved = try await store.saveBody(
            localID: first.localID,
            body: OfflineNoteBody(title: nil, content: "second", contentJSON: raw, tags: ["标签"])
        )
        try await store.close()

        let reopened = try await open()
        let restored = try unwrap(try await reopened.note(localID: "local-note"))
        XCTAssertEqual(restored.body.content, "second")
        XCTAssertEqual(restored.body.contentJSON, raw)
        XCTAssertEqual(restored.body.tags, ["标签"])
        XCTAssertEqual(restored.bodyRevision, saved.bodyRevision)
        XCTAssertFalse(restored.isSynchronized)
        XCTAssertFalse(restored.isPublic)
        XCTAssertNil(restored.serverAssetID)
        try await reopened.close()
    }

    // Break caught: deriving a store path from just actor, environment, or ambiguous concatenation.
    func testActorAndEnvironmentStoresAreIsolated() async throws {
        let first = try await open()
        _ = try await first.create(body: body("private"), localID: "same-local-id")
        let otherActor = try await NoteLocalStore.open(
            rootURL: root, scope: NoteStoreScope(actorID: "actor-b", environmentID: "local")
        )
        let production = try await NoteLocalStore.open(
            rootURL: root, scope: NoteStoreScope(actorID: "actor-a", environmentID: "production")
        )
        let others = try await otherActor.notes()
        let prodNotes = try await production.notes()
        XCTAssertTrue(others.isEmpty)
        XCTAssertTrue(prodNotes.isEmpty)
        XCTAssertNotEqual(first.directoryURL, otherActor.directoryURL)
        XCTAssertNotEqual(first.directoryURL, production.directoryURL)
        try await first.close()
        try await otherActor.close()
        try await production.close()
    }

    // Break caught: rewriting a frozen request when a later edit arrives, or ACKing that later edit.
    func testFrozenRequestSurvivesRestartAndItsAckDoesNotAcknowledgeNewerBody() async throws {
        let store = try await open()
        let first = try await store.create(body: body("sent body"), localID: "local-note")
        let bytes = Data(#"{"content":"sent body","tags":[]}"#.utf8)
        let operation = createOperation(first, bytes: bytes)
        _ = try await store.freeze(localID: first.localID, operation: operation, expectedGeneration: first.generation)
        _ = try await store.saveBody(localID: first.localID, body: body("newer body"))
        try await store.close()

        let reopened = try await open()
        let recovered = try unwrap(try await reopened.note(localID: first.localID))
        XCTAssertEqual(recovered.pendingOperation?.requestBody, bytes)
        XCTAssertEqual(recovered.pendingOperation?.operationID, "op-create")
        let acknowledged = try await reopened.acknowledge(localID: first.localID, receipt: receipt("op-create"))
        XCTAssertEqual(acknowledged.localID, "local-note")
        XCTAssertEqual(acknowledged.serverAssetID, "asset-a")
        XCTAssertEqual(acknowledged.body.content, "newer body")
        XCTAssertEqual(acknowledged.acknowledgedBodyRevision, first.bodyRevision)
        XCTAssertGreaterThan(acknowledged.bodyRevision, acknowledged.acknowledgedBodyRevision)
        XCTAssertNil(acknowledged.pendingOperation)
        XCTAssertFalse(acknowledged.isSynchronized)
        try await reopened.close()
    }

    // Break caught: a lifecycle-only response marking unpublished text as synchronized.
    func testDeleteAcknowledgmentKeepsUnsentBodyAndRestoreCanStillFindIt() async throws {
        let store = try await open()
        let initial = try await syncedNote(in: store)
        _ = try await store.saveBody(localID: initial.localID, body: body("never published"))
        let deleted = try await store.setLifecycle(localID: initial.localID, lifecycle: .trashed)
        let operation = NotePendingOperation(
            operationID: "op-delete", kind: .delete, serverAssetID: "asset-a",
            bodyRevision: nil, lifecycle: .trashed, baseSyncToken: "token-1",
            requestBody: Data(#"{"base_sync_token":"token-1"}"#.utf8)
        )
        _ = try await store.freeze(localID: initial.localID, operation: operation, expectedGeneration: deleted.generation)
        let acknowledged = try await store.acknowledge(
            localID: initial.localID, receipt: receipt("op-delete", token: "token-2", lifecycle: .trashed)
        )
        XCTAssertEqual(acknowledged.acknowledgedBodyRevision, initial.acknowledgedBodyRevision)
        XCTAssertEqual(acknowledged.confirmedLifecycle, .trashed)
        XCTAssertEqual(acknowledged.body.content, "never published")
        XCTAssertFalse(acknowledged.isSynchronized)
        try await store.close()
        let reopened = try await open()
        let restored = try await reopened.setLifecycle(localID: initial.localID, lifecycle: .active)
        XCTAssertEqual(restored.body.content, "never published")
        XCTAssertEqual(restored.confirmedLifecycle, .trashed)
        XCTAssertEqual(restored.baseSyncToken, "token-2")
        try await reopened.close()
    }

    // Break caught: applying a read started before local typing to the new working copy.
    func testStaleRemoteReadCannotOverwriteLocalSave() async throws {
        let store = try await open()
        let original = try await syncedNote(in: store)
        let edited = try await store.saveBody(localID: original.localID, body: body("local wins until resolution"))
        let result = try await store.applyRemote(
            remote("remote new", token: "token-2"), localID: original.localID,
            expectedGeneration: original.generation
        )
        XCTAssertNil(result)
        let persisted = try unwrap(try await store.note(localID: original.localID))
        XCTAssertEqual(persisted, edited)
        try await store.close()
    }

    // Break caught: replacing a dirty working copy or advancing its baseline on remote conflict.
    func testDirtyReconciliationRetainsBothBodiesWithoutAdvancingBaseline() async throws {
        let store = try await open()
        let original = try await syncedNote(in: store)
        let edited = try await store.saveBody(localID: original.localID, body: body("local draft"))
        let conflicted = try unwrap(try await store.applyRemote(
            remote("remote draft", token: "token-2"), localID: edited.localID,
            expectedGeneration: edited.generation
        ))
        XCTAssertEqual(conflicted.body.content, "local draft")
        XCTAssertEqual(conflicted.remoteSnapshot?.body.content, "remote draft")
        XCTAssertEqual(conflicted.baseSyncToken, "token-1")
        XCTAssertFalse(conflicted.isSynchronized)
        try await store.close()
    }

    func testAuthorizedRemoteReadUnblocksEditedUnavailableNoteWithUnchangedBaseline() async throws {
        let store = try await open()
        let original = try await syncedNote(in: store)
        try await store.recordSyncIssue(localID: original.localID, issue: "remote_unavailable")
        let edited = try await store.saveBody(localID: original.localID, body: body("offline draft"))
        let cleared = try unwrap(try await store.applyRemote(
            remote("server body", token: "token-1"), localID: original.localID, expectedGeneration: edited.generation
        ))
        XCTAssertNil(cleared.syncIssue)
        XCTAssertNil(cleared.remoteSnapshot)
        XCTAssertEqual(cleared.body, edited.body)
        XCTAssertEqual(cleared.baseSyncToken, original.baseSyncToken)
        XCTAssertTrue(cleared.hasUnacknowledgedBody)
        try await store.close()
    }

    // Break caught: accepting a receipt for another request or leaving a failed mutation in the context.
    func testWrongReceiptAndSecondFreezeDoNotMutatePendingOperation() async throws {
        let store = try await open()
        let first = try await store.create(body: body("original"), localID: "local-note")
        let frozen = try await store.freeze(localID: first.localID, operation: createOperation(first), expectedGeneration: first.generation)
        do {
            _ = try await store.acknowledge(localID: first.localID, receipt: receipt("other-operation"))
            XCTFail("Unrelated receipt must not confirm an operation")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidReceipt) }
        do {
            _ = try await store.freeze(localID: first.localID, operation: createOperation(first), expectedGeneration: frozen.generation)
            XCTFail("An unresolved frozen operation must not be replaced")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .pendingOperationExists) }
        _ = try await store.create(body: body("other note"), localID: "other")
        let unchanged = try await store.note(localID: first.localID)
        XCTAssertEqual(unchanged, frozen)
        try await store.close()
    }

    // Break caught: yielding between read and save so simultaneous saves lose revisions.
    func testConcurrentLocalWritesCommitWithoutLosingRevisionUpdates() async throws {
        let store = try await open()
        let original = try await store.create(body: body("seed"), localID: "local-note")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = try await store.saveBody(localID: "local-note", body: OfflineNoteBody(content: "edit-\(index)"))
                }
            }
            try await group.waitForAll()
        }
        let final = try unwrap(try await store.note(localID: original.localID))
        XCTAssertEqual(final.bodyRevision, original.bodyRevision + 20)
        XCTAssertEqual(final.generation, original.generation + 20)
        try await store.close()
    }

    func testStorageOpenFailureDoesNotDeleteExistingData() async throws {
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("existing data that is not a directory".utf8)
        try original.write(to: root)
        do {
            _ = try await open()
            XCTFail("Opening an invalid store directory must fail")
        } catch {
            XCTAssertEqual(try Data(contentsOf: root), original)
        }
    }

    // Real Core Data validation failure must roll back, including before a subsequent successful save.
    func testFailedPersistentTransactionCannotLeakIntoNextSuccessfulCommit() async throws {
        let store = try await open()
        let saved = try await store.create(body: body("retained"), localID: "local-note")
        do {
            try await store.transaction { context in
                let row = try XCTUnwrap(NoteLocalStore.row(localID: "local-note", in: context))
                row.setValue(nil, forKey: "payload") // Required attribute: force actual store validation failure.
            }
            XCTFail("Invalid persistent row must not commit")
        } catch {}
        _ = try await store.create(body: body("healthy later transaction"), localID: "later")
        let retained = try await store.note(localID: saved.localID)
        XCTAssertEqual(retained, saved)
        try await store.close()
    }

    func testFutureRecordVersionFailsClosedWithoutDeletingOriginalBytes() async throws {
        let store = try await open()
        _ = try await store.create(body: body("unmigrated private content"), localID: "local-note")
        let futureBytes: Data = try await store.transaction { context in
            let row = try XCTUnwrap(NoteLocalStore.row(localID: "local-note", in: context))
            let bytes = try XCTUnwrap(row.value(forKey: "payload") as? Data)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            object["formatVersion"] = 999
            let future = try JSONSerialization.data(withJSONObject: object)
            row.setValue(future, forKey: "payload")
            return future
        }
        try await store.close()
        let reopened = try await open()
        do {
            _ = try await reopened.notes()
            XCTFail("Unknown format requires migration, never deletion/rebuild")
        } catch { XCTAssertEqual(error as? NoteLocalStoreError, .unsupportedStoreVersion) }
        let retainedBytes: Data = try await reopened.transaction { context in
            let row = try XCTUnwrap(NoteLocalStore.row(localID: "local-note", in: context))
            return try XCTUnwrap(row.value(forKey: "payload") as? Data)
        }
        XCTAssertEqual(retainedBytes, futureBytes)
        try await reopened.close()
    }

    func testMissingAttachmentCannotBeCommittedAsSavedBody() async throws {
        let store = try await open()
        let original = try await store.create(body: body("saved body"), localID: "local-note")
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let attachment = try files.retain(data: Data("photo".utf8), filename: "photo.png", mimeType: "image/png")
        try FileManager.default.removeItem(at: files.directoryURL.appendingPathComponent(attachment.relativePath))
        do {
            _ = try await store.saveBody(localID: original.localID, body: body("body with unavailable photo"), attachments: [attachment])
            XCTFail("Body referencing missing bytes must not be acknowledged as locally saved")
        } catch {}
        let unchanged = try await store.note(localID: original.localID)
        XCTAssertEqual(unchanged, original)
        try await store.close()
    }

    private func unwrap(_ value: OfflineNote?, file: StaticString = #filePath, line: UInt = #line) throws -> OfflineNote {
        try XCTUnwrap(value, file: file, line: line)
    }

    private func open() async throws -> NoteLocalStore {
        try await NoteLocalStore.open(rootURL: root, scope: scope)
    }

    private func body(_ content: String) -> OfflineNoteBody { OfflineNoteBody(content: content) }

    private func createOperation(_ note: OfflineNote, bytes: Data = Data("{}".utf8)) -> NotePendingOperation {
        NotePendingOperation(
            operationID: "op-create", kind: .create, serverAssetID: nil,
            bodyRevision: note.bodyRevision, lifecycle: .active, baseSyncToken: nil, requestBody: bytes
        )
    }

    private func receipt(_ operationID: String, token: String = "token-1", lifecycle: NoteLifecycle = .active) -> NoteSyncReceipt {
        NoteSyncReceipt(operationID: operationID, assetID: "asset-a", syncToken: token, noteDocumentVersionID: "note-v1", lifecycle: lifecycle)
    }

    private func remote(_ content: String, token: String = "token-1") -> NoteRemoteSnapshot {
        NoteRemoteSnapshot(assetID: "asset-a", syncToken: token, body: body(content), lifecycle: .active, isPublic: true)
    }

    private func syncedNote(in store: NoteLocalStore) async throws -> OfflineNote {
        try unwrap(try await store.applyRemote(remote("server body"), localID: nil, expectedGeneration: nil))
    }
}
