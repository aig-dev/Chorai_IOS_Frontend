import Foundation
import XCTest
@testable import CoreFlow

/// Opt-in: uses the actual local API and an ordinary authenticated QA account.
/// Tokens remain in the caller-owned file, outside test output and the repo.
final class NoteSyncLiveAPITests: XCTestCase {
    private func unwrap<T>(_ value: T?) throws -> T { try XCTUnwrap(value) }

    private func fixture() async throws -> (NoteLocalStore, M1LiveTransport) {
        guard let path = ProcessInfo.processInfo.environment["CHORAI_M1_SESSION_FILE"] else {
            throw XCTSkip("Local M1 API session was not supplied")
        }
        let object = try unwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let login = try unwrap(object["login"] as? [String: Any])
        let data = try unwrap(login["data"] as? [String: Any])
        let user = try unwrap(data["user"] as? [String: Any])
        let token = try unwrap(data["token"] as? String)
        let actor = try unwrap(user["id"] as? String)
        let endpoint = try unwrap(object["api_base_url"] as? String)
        guard let host = URL(string: endpoint)?.host, ["127.0.0.1", "localhost"].contains(host) else { throw XCTSkip("Live API fixture must be loopback") }
        let scope = NoteStoreScope(actorID: actor, environmentID: endpoint)
        let directory = URL(fileURLWithPath: "/tmp/chorai-m1-20261105/live-client-tests").appendingPathComponent(UUID().uuidString)
        return (try await NoteLocalStore.open(rootURL: directory, scope: scope), M1LiveTransport(scope: scope, token: token))
    }

    func testLiveCommittedResponseLossReopensAndReplaysOneVersion() async throws {
        let (store, service) = try await fixture()
        let note = try await store.create(body: OfflineNoteBody(content: "M1 live lost ACK " + UUID().uuidString))
        await service.loseNextAcknowledgment()
        let sync = try NoteSyncCoordinator(store: store, service: service)
        await sync.resume(); await sync.synchronize(); await sync.suspend()
        let pending = try unwrap(try await store.note(localID: note.localID)?.pendingOperation)
        let root = store.directoryURL.deletingLastPathComponent()
        try await store.close()
        let reopened = try await NoteLocalStore.open(rootURL: root, scope: service.scope)
        let next = try NoteSyncCoordinator(store: reopened, service: service)
        await next.resume(); await next.synchronize(forceRetry: true)
        let saved = try unwrap(try await reopened.note(localID: note.localID))
        XCTAssertTrue(saved.isSynchronized)
        let requests = await service.operations
        XCTAssertEqual(requests[0].operationID, pending.operationID)
        XCTAssertEqual(requests[0].requestBody, pending.requestBody)
        XCTAssertEqual(requests[0].operationID, requests[1].operationID)
        XCTAssertEqual(requests[0].requestBody, requests[1].requestBody)
        let replies = await service.receipts
        XCTAssertEqual(replies[0], replies[1])
        let remote = try await service.detail(assetID: try unwrap(saved.serverAssetID))
        XCTAssertEqual(remote.body.content.trimmingCharacters(in: .whitespacesAndNewlines), note.body.content)
        await next.suspend(); try await reopened.close()
    }

    func testLiveConcurrentWriterConflictPreservesBothAndCopyDoesNotOverwrite() async throws {
        let (store, service) = try await fixture()
        let note = try await store.create(body: OfflineNoteBody(content: "M1 live conflict base " + UUID().uuidString))
        let sync = try NoteSyncCoordinator(store: store, service: service)
        await sync.resume(); await sync.synchronize()
        let base = try unwrap(try await store.note(localID: note.localID))
        var other = base
        other.body = OfflineNoteBody(content: "M1 second writer wins")
        other.bodyRevision += 1
        _ = try await service.send(try unwrap(NoteSyncPayload.operation(for: other, operationID: UUID().uuidString)))
        _ = try await store.saveBody(localID: note.localID, body: OfflineNoteBody(content: "M1 local draft kept"))
        await sync.synchronize(forceRetry: true)
        let conflict = try unwrap(try await store.note(localID: note.localID))
        XCTAssertEqual(conflict.body.content, "M1 local draft kept")
        XCTAssertEqual(conflict.remoteSnapshot?.body.content.trimmingCharacters(in: .whitespacesAndNewlines), "M1 second writer wins")
        XCTAssertEqual(conflict.syncIssue, "conflict")
        let copy = try await sync.saveLocalAsNewNote(localID: note.localID)
        await sync.synchronize(forceRetry: true)
        let retained = try unwrap(try await store.note(localID: copy.localID))
        XCTAssertTrue(retained.isSynchronized)
        XCTAssertNotEqual(retained.serverAssetID, base.serverAssetID)
        let remote = try await service.detail(assetID: try unwrap(base.serverAssetID))
        XCTAssertEqual(remote.body.content.trimmingCharacters(in: .whitespacesAndNewlines), "M1 second writer wins")
        await sync.suspend(); try await store.close()
    }

    func testLiveDeleteRestoreRejectsOldBodyBaseline() async throws {
        let (store, service) = try await fixture()
        let note = try await store.create(body: OfflineNoteBody(content: "M1 lifecycle baseline " + UUID().uuidString))
        let sync = try NoteSyncCoordinator(store: store, service: service)
        await sync.resume(); await sync.synchronize(); await sync.suspend()
        let base = try unwrap(try await store.note(localID: note.localID))
        var deleted = base; deleted.desiredLifecycle = .trashed
        let deletion = try await service.send(try unwrap(NoteSyncPayload.operation(for: deleted, operationID: UUID().uuidString)))
        var restore = base; restore.confirmedLifecycle = .trashed; restore.baseSyncToken = deletion.syncToken
        let restored = try await service.send(try unwrap(NoteSyncPayload.operation(for: restore, operationID: UUID().uuidString)))
        XCTAssertNotEqual(restored.syncToken, base.baseSyncToken)
        var old = base; old.bodyRevision += 1; old.body = OfflineNoteBody(content: "must not overwrite restored note")
        do {
            _ = try await service.send(try unwrap(NoteSyncPayload.operation(for: old, operationID: UUID().uuidString)))
            XCTFail("Old body baseline was accepted after delete/restore")
        } catch { XCTAssertEqual(error as? NoteSyncFailure, .staleVersion) }
        try await store.close()
    }
}

private actor M1LiveTransport: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    private let token: String
    private var loseAcknowledgment = false
    private(set) var operations: [NotePendingOperation] = []
    private(set) var receipts: [NoteSyncReceipt] = []
    init(scope: NoteStoreScope, token: String) { self.scope = scope; self.token = token }
    func loseNextAcknowledgment() { loseAcknowledgment = true }
    func manifest() async throws -> NoteSyncManifest {
        try NoteSyncHTTP.payload(NoteSyncManifest.self, from: await request("/api/cards/sync-manifest"))
    }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        try NoteSyncHTTP.snapshot(from: await request("/api/cards/" + assetID + "?sync=1"), actorID: scope.actorID)
    }
    func send(_ op: NotePendingOperation) async throws -> NoteSyncReceipt {
        operations.append(op)
        let path: String
        switch op.kind {
        case .create: path = "/api/cards"
        case .restore: path = "/api/cards/trash/" + (op.serverAssetID ?? "") + "/restore"
        default: path = "/api/cards/" + (op.serverAssetID ?? "")
        }
        let method = op.kind == .update ? "PUT" : op.kind == .delete ? "DELETE" : "POST"
        let receipt = try NoteSyncHTTP.receipt(from: await request(path, method: method, body: op.requestBody, key: op.operationID))
        receipts.append(receipt)
        if loseAcknowledgment { loseAcknowledgment = false; throw NoteSyncFailure.transient(retryAfter: 60) }
        return receipt
    }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.unsupportedDocument }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.unsupportedDocument }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, key: String? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: scope.environmentID + path)!)
        req.httpMethod = method; req.httpBody = body
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let (bytes, response) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        guard (200..<300).contains(http.statusCode) else { throw NoteSyncHTTP.failure(status: http.statusCode, body: bytes, retryAfter: http.value(forHTTPHeaderField: "Retry-After")) }
        return bytes
    }
}
