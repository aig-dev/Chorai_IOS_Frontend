import CryptoKit
import Foundation
import XCTest
@testable import CoreFlow

/// Explicitly opt in with an ordinary local QA session. No production URL or
/// credential enters test output; all requests use the actual loopback API.
final class NoteSyncM2LiveAPITests: XCTestCase {
    private func unwrap<T>(_ value: T?) throws -> T { try XCTUnwrap(value) }

    private func fixture() async throws -> (URL, NoteLocalStore, M2LiveTransport, Data) {
        guard let path = ProcessInfo.processInfo.environment["CHORAI_M2_SESSION_FILE"],
              let image = ProcessInfo.processInfo.environment["CHORAI_M2_IMAGE_FILE"] else { throw XCTSkip("Local M2 API fixture not supplied") }
        let object = try unwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let login = try unwrap(object["login"] as? [String: Any]); let data = try unwrap(login["data"] as? [String: Any])
        let user = try unwrap(data["user"] as? [String: Any]); let token = try unwrap(data["token"] as? String)
        let endpoint = try unwrap(object["api_base_url"] as? String)
        guard let host = URL(string: endpoint)?.host, ["localhost", "127.0.0.1"].contains(host) else { throw XCTSkip("M2 fixture must be loopback") }
        let scope = NoteStoreScope(actorID: try unwrap(user["id"] as? String), environmentID: endpoint)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chorai-m2-20261105/live-client-tests/" + UUID().uuidString)
        return (root, try await NoteLocalStore.open(rootURL: root, scope: scope), M2LiveTransport(scope: scope, token: token), try Data(contentsOf: URL(fileURLWithPath: image)))
    }

    private func imageNote(_ store: NoteLocalStore, bytes: Data, text: String) async throws -> OfflineNote {
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let attachment = try files.retain(data: bytes, filename: "m2-live.png", mimeType: "image/png")
        let note = try await store.create(body: OfflineNoteBody(content: ""))
        return try await store.saveBody(localID: note.localID, body: body(text, attachment: attachment), attachments: [attachment])
    }

    private func body(_ text: String, attachment: NoteLocalAttachment) -> OfflineNoteBody {
        let blocks: [[String: Any]] = [
            ["id":"text", "type":"paragraph", "content":[["type":"text", "text":text, "styles":[:]]], "children":[]],
            ["id":"photo", "type":"image", "props":["mediaRef":NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID)], "children":[]]
        ]
        return OfflineNoteBody(content: text, contentJSON: String(decoding: try! JSONSerialization.data(withJSONObject: blocks, options: [.sortedKeys]), as: UTF8.self))
    }

    func testLiveM2UploadAndBodyResponseLossReopenWithStableIdentities() async throws {
        let (root, store, service, bytes) = try await fixture()
        let note = try await imageNote(store, bytes: bytes, text: "M2 live lost image ACK " + UUID().uuidString)
        let first = try NoteSyncCoordinator(store: store, service: service)
        await service.loseNextUploadACK(); await first.resume(); await first.synchronize(); await first.suspend()
        let waiting = try unwrap(try await store.note(localID: note.localID))
        XCTAssertNil(waiting.pendingOperation); XCTAssertNil(waiting.attachments.first?.mediaRef)
        try await store.close()

        let secondStore = try await NoteLocalStore.open(rootURL: root, scope: service.scope)
        let second = try NoteSyncCoordinator(store: secondStore, service: service)
        await service.loseNextBodyACK(); await second.resume(); await second.synchronize(forceRetry: true); await second.suspend()
        let pending = try unwrap(try await secondStore.note(localID: note.localID)?.pendingOperation)
        try await secondStore.close()

        let reopened = try await NoteLocalStore.open(rootURL: root, scope: service.scope)
        let third = try NoteSyncCoordinator(store: reopened, service: service)
        await third.resume(); await third.synchronize(forceRetry: true)
        let saved = try unwrap(try await reopened.note(localID: note.localID))
        XCTAssertTrue(saved.isSynchronized)
        let uploads = await service.uploads
        XCTAssertEqual(uploads.count, 2); XCTAssertEqual(uploads[0], uploads[1])
        let operations = await service.operations
        XCTAssertEqual(operations.count, 2)
        XCTAssertEqual(operations[0].operationID, pending.operationID)
        XCTAssertEqual(operations[0].operationID, operations[1].operationID)
        XCTAssertEqual(operations[0].requestBody, operations[1].requestBody)
        let receipts = await service.receipts; XCTAssertEqual(receipts[0], receipts[1])
        let remote = try await service.detail(assetID: try unwrap(saved.serverAssetID))
        XCTAssertEqual(remote.body.content.trimmingCharacters(in: .whitespacesAndNewlines), note.body.content)
        let ref = try unwrap(saved.attachments.first?.mediaRef)
        let downloaded = try await service.downloadAttachment(assetID: try unwrap(saved.serverAssetID), mediaRef: ref)
        XCTAssertEqual(downloaded.data, bytes)
        try evidence("lost-ack", ["asset_id":try unwrap(saved.serverAssetID), "media_ref":ref, "upload_id":uploads[0], "operation_id":pending.operationID, "image_sha256":saved.attachments[0].sha256])
        await third.suspend(); try await reopened.close()
    }

    func testLiveM2OfflineDeleteRestoreKeepsDirtyImageBodyUntilRestore() async throws {
        let (root, store, service, bytes) = try await fixture()
        let note = try await imageNote(store, bytes: bytes, text: "M2 live lifecycle base " + UUID().uuidString)
        let first = try NoteSyncCoordinator(store: store, service: service)
        await first.resume(); await first.synchronize(); await first.suspend()
        let base = try unwrap(try await store.note(localID: note.localID))
        let changed = body("M2 retained dirty image body", attachment: try unwrap(base.attachments.first))
        _ = try await store.saveBody(localID: note.localID, body: changed)
        _ = try await store.setLifecycle(localID: note.localID, lifecycle: .trashed)
        try await store.close()

        let deletedStore = try await NoteLocalStore.open(rootURL: root, scope: service.scope)
        let localTrash = try unwrap(try await deletedStore.note(localID: note.localID))
        XCTAssertEqual(localTrash.desiredLifecycle, .trashed)
        XCTAssertEqual(localTrash.body, changed)
        let files = try NoteAttachmentFiles(directoryURL: deletedStore.directoryURL.appendingPathComponent("attachments"))
        XCTAssertEqual(try files.read(try unwrap(localTrash.attachments.first)), bytes)
        let second = try NoteSyncCoordinator(store: deletedStore, service: service)
        await second.resume(); await second.synchronize(forceRetry: true); await second.suspend()
        let deleted = try unwrap(try await deletedStore.note(localID: note.localID))
        XCTAssertEqual(deleted.confirmedLifecycle, .trashed)
        XCTAssertEqual(deleted.acknowledgedBodyRevision, base.acknowledgedBodyRevision)
        XCTAssertTrue(deleted.hasUnacknowledgedBody)
        let remoteTrash = try await service.detail(assetID: try unwrap(base.serverAssetID))
        XCTAssertEqual(remoteTrash.lifecycle, .trashed)
        XCTAssertEqual(remoteTrash.body.content.trimmingCharacters(in: .whitespacesAndNewlines), note.body.content)
        _ = try await deletedStore.setLifecycle(localID: note.localID, lifecycle: .active)
        try await deletedStore.close()

        let reopened = try await NoteLocalStore.open(rootURL: root, scope: service.scope)
        let third = try NoteSyncCoordinator(store: reopened, service: service)
        await third.resume(); await third.synchronize(forceRetry: true)
        let restored = try unwrap(try await reopened.note(localID: note.localID))
        XCTAssertTrue(restored.isSynchronized); XCTAssertEqual(restored.body, changed)
        let operations = await service.operations
        XCTAssertEqual(operations.map(\.kind), [.create, .delete, .restore, .update])
        let uploads = await service.uploads; XCTAssertEqual(uploads.count, 1)
        let remote = try await service.detail(assetID: try unwrap(restored.serverAssetID))
        XCTAssertEqual(remote.lifecycle, .active)
        XCTAssertEqual(remote.body.content.trimmingCharacters(in: .whitespacesAndNewlines), changed.content)
        let downloaded = try await service.downloadAttachment(assetID: try unwrap(restored.serverAssetID), mediaRef: try unwrap(restored.attachments.first?.mediaRef))
        XCTAssertEqual(downloaded.data, bytes)
        try evidence("lifecycle", ["asset_id":try unwrap(restored.serverAssetID), "media_ref":try unwrap(restored.attachments.first?.mediaRef), "body_revision":restored.bodyRevision, "acknowledged_body_revision":restored.acknowledgedBodyRevision])
        await third.suspend(); try await reopened.close()
    }

    func testLiveM2RecoversPersistedTransientFailureWithFrozenRequest() async throws {
        let (root, initialStore, service, bytes) = try await fixture()
        let created = try await imageNote(initialStore, bytes: bytes, text: "M2 persisted transport failure " + UUID().uuidString)
        let first = try NoteSyncCoordinator(store: initialStore, service: service)
        await service.failNextBodyBeforeTransmission()
        await first.resume(); await first.synchronize(); await first.suspend()
        let interrupted = try unwrap(try await initialStore.note(localID: created.localID))
        XCTAssertFalse(interrupted.isSynchronized)
        XCTAssertGreaterThan(try unwrap(interrupted.pendingOperation).attemptCount, 0)
        let beforeRecovery = await service.receipts
        XCTAssertTrue(beforeRecovery.isEmpty)
        try await initialStore.close()

        let store = try await NoteLocalStore.open(rootURL: root, scope: service.scope)
        let note = try unwrap(try await store.notes().first { ($0.pendingOperation?.attemptCount ?? 0) > 0 })
        let pending = try unwrap(note.pendingOperation)
        XCTAssertEqual(pending, interrupted.pendingOperation)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize(forceRetry: true)
        let saved = try unwrap(try await store.note(localID: note.localID))
        XCTAssertTrue(saved.isSynchronized)
        XCTAssertEqual(saved.body, note.body)
        let operations = await service.operations
        XCTAssertEqual(operations.count, 2)
        XCTAssertTrue(operations.allSatisfy { $0.operationID == pending.operationID && $0.requestBody == pending.requestBody })
        let uploads = await service.uploads
        XCTAssertEqual(uploads.count, 1)
        let remote = try await service.detail(assetID: try unwrap(saved.serverAssetID))
        XCTAssertEqual(remote.body.content.trimmingCharacters(in: .whitespacesAndNewlines), note.body.content)
        let downloaded = try await service.downloadAttachment(assetID: try unwrap(saved.serverAssetID), mediaRef: try unwrap(saved.attachments.first?.mediaRef))
        XCTAssertEqual(downloaded.data, bytes)
        try evidence("transient-recovery", ["asset_id":try unwrap(saved.serverAssetID), "operation_id":pending.operationID, "synchronized":saved.isSynchronized])
        await coordinator.suspend(); try await store.close()
    }

    private func evidence(_ name: String, _ value: [String: Any]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chorai-m2-20261105")
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: root.appendingPathComponent("live-" + name + "-evidence.json"))
    }
}

private actor M2LiveTransport: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    private let token: String
    private var dropUpload = false
    private var dropBody = false
    private var failBody = false
    private(set) var uploads: [String] = []
    private(set) var operations: [NotePendingOperation] = []
    private(set) var receipts: [NoteSyncReceipt] = []
    init(scope: NoteStoreScope, token: String) { self.scope = scope; self.token = token }
    func loseNextUploadACK() { dropUpload = true }
    func loseNextBodyACK() { dropBody = true }
    func failNextBodyBeforeTransmission() { failBody = true }
    func manifest() async throws -> NoteSyncManifest {
        let value = try NoteSyncHTTP.payload(NoteSyncManifest.self, from: await request("/api/cards/sync-manifest"))
        guard value.protocolVersion == 3 else { throw NoteSyncFailure.notReady }; return value
    }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        try NoteSyncHTTP.snapshot(from: await request("/api/cards/" + assetID + "?sync=1"), actorID: scope.actorID)
    }
    func send(_ op: NotePendingOperation) async throws -> NoteSyncReceipt {
        operations.append(op)
        if failBody { failBody = false; throw NoteSyncFailure.transient(retryAfter: 60) }
        let path = op.kind == .create ? "/api/cards" : op.kind == .restore ? "/api/cards/trash/" + op.serverAssetID! + "/restore" : "/api/cards/" + op.serverAssetID!
        let method = op.kind == .update ? "PUT" : op.kind == .delete ? "DELETE" : "POST"
        let receipt = try NoteSyncHTTP.receipt(from: await request(path, method: method, body: op.requestBody, key: op.operationID))
        receipts.append(receipt)
        if dropBody { dropBody = false; throw NoteSyncFailure.transient(retryAfter: 60) }
        return receipt
    }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt {
        uploads.append(attachment.uploadID)
        let boundary = "M2-" + UUID().uuidString
        var body = Data(("--"+boundary+"\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\ninline\r\n--"+boundary+"\r\nContent-Disposition: form-data; name=\"file\"; filename=\"m2.png\"\r\nContent-Type: image/png\r\n\r\n").utf8)
        body.append(data); body.append(Data(("\r\n--"+boundary+"--\r\n").utf8))
        let result = try NoteSyncHTTP.payload(NoteSyncUploadReceipt.self, from: await request("/api/v1/media/upload", method: "POST", body: body, key: attachment.uploadID, contentType: "multipart/form-data; boundary=" + boundary))
        if dropUpload { dropUpload = false; throw NoteSyncFailure.transient(retryAfter: 60) }
        return result
    }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment {
        struct Media: Decodable { let public_url: String; let mime: String; let sha256: String; let size_bytes: Int }
        let meta = try NoteSyncHTTP.payload(Media.self, from: await request("/api/v1/media/" + mediaRef + "?asset_id=" + assetID))
        let bytes = try await request(meta.public_url)
        guard bytes.count == meta.size_bytes, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == meta.sha256 else { throw NoteSyncFailure.invalidResponse }
        return NoteSyncDownloadedAttachment(data: bytes, filename: mediaRef, mimeType: meta.mime)
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, key: String? = nil, contentType: String = "application/json") async throws -> Data {
        var req = URLRequest(url: URL(string: scope.environmentID + path)!)
        req.httpMethod = method; req.httpBody = body; req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let key { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let (bytes, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NoteSyncFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = NoteSyncHTTP.failure(status: http.statusCode, body: bytes, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            print("M2 loopback HTTP failure", method, path, http.statusCode, failure)
            throw failure
        }
        return bytes
    }
}
