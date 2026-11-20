import Foundation
import XCTest
@testable import CoreFlow

final class NoteSyncCoordinatorTests: XCTestCase {
    private var root: URL!
    private let scope = NoteStoreScope(actorID: "actor-a", environmentID: "local")

    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDownWithError() throws { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
    private func open() async throws -> NoteLocalStore { try await NoteLocalStore.open(rootURL: root, scope: scope) }
    private func unwrap<T>(_ value: T?) throws -> T { try XCTUnwrap(value) }
    private func body(_ text: String) -> OfflineNoteBody { OfflineNoteBody(content: text, tags: ["local"]) }

    func testMediaLifecycleProtocolDeliversImageThenDeleteAndRestore() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 3, complete: true, notes: []))
        let note = try await makeImageNote(store)
        let sync = try NoteSyncCoordinator(store: store, service: service)
        await sync.resume(); await sync.synchronize(forceRetry: true)
        let created = try unwrap(try await store.note(localID: note.localID))
        XCTAssertTrue(created.isSynchronized)
        _ = try await store.setLifecycle(localID: note.localID, lifecycle: .trashed)
        await sync.synchronize(forceRetry: true)
        let deleted = try unwrap(try await store.note(localID: note.localID))
        XCTAssertEqual(deleted.confirmedLifecycle, .trashed)
        XCTAssertEqual(deleted.acknowledgedBodyRevision, created.acknowledgedBodyRevision)
        _ = try await store.setLifecycle(localID: note.localID, lifecycle: .active)
        await sync.synchronize(forceRetry: true)
        let restored = try unwrap(try await store.note(localID: note.localID))
        XCTAssertTrue(restored.isSynchronized)
        XCTAssertEqual(restored.body, note.body)
        let operations = await service.operations
        XCTAssertEqual(operations.map(\.kind), [.create, .delete, .restore])
        let uploads = await service.uploadIDs
        XCTAssertEqual(uploads.count, 1)
        await sync.suspend(); try await store.close()
    }

    func testMediaProtocolResumesM1ImageWithoutUnblockingUnknownDocuments() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let image = try await makeImageNote(store)
        let unknownRaw = #"{"blocks":[{"id":"mindmap","type":"mindmap","props":{"future":"keep"},"children":[]}]}"#
        let unknown = try await store.create(body: OfflineNoteBody(content: "unsupported", contentJSON: unknownRaw))
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 2, complete: true, notes: []))
        let sync = try NoteSyncCoordinator(store: store, service: service)
        await sync.resume(); await sync.synchronize(forceRetry: true)
        let blocked = try await store.note(localID: image.localID)
        XCTAssertEqual(blocked?.syncIssue, "unsupported_document")
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 3, complete: true, notes: []))
        await sync.synchronize(forceRetry: true)
        let saved = try await store.note(localID: image.localID)
        XCTAssertTrue(saved?.isSynchronized == true)
        let retained = try await store.note(localID: unknown.localID)
        XCTAssertEqual(retained?.body.contentJSON, unknownRaw)
        XCTAssertEqual(retained?.syncIssue, "unsupported_document")
        let operations = await service.operations
        XCTAssertEqual(operations.count, 1)
        await sync.suspend(); try await store.close()
    }

    func testTextOnlyRetainedUnsupportedPendingDoesNotBlockOtherTextNotes() async throws {
        for kind in [NotePendingOperation.Kind.create, .delete] {
            let store = try await NoteLocalStore.open(rootURL: root.appendingPathComponent(UUID().uuidString), scope: scope)
            var retained: OfflineNote
            if kind == .delete {
                let remote = NoteSyncTestTransport.snapshot("old-remote", token: "old-base", text: "keep")
                retained = try unwrap(try await store.applyRemote(remote, localID: nil, expectedGeneration: nil))
                retained = try await store.setLifecycle(localID: retained.localID, lifecycle: .trashed)
            } else {
                let raw = #"{"blocks":[{"id":"photo","type":"image","props":{"mediaRef":"med_aaaaaaaaaaaaaaaa"},"children":[]}]}"#
                retained = try await store.create(body: OfflineNoteBody(content: "retained image", contentJSON: raw), localID: "a-old-image")
            }
            let pending = try unwrap(NoteSyncPayload.operation(for: retained, operationID: "original-pending-key"))
            _ = try await store.freeze(localID: retained.localID, operation: pending, expectedGeneration: retained.generation)
            let text = try await store.create(body: body("eligible text"), localID: "zz-m1-text")
            let service = NoteSyncTestTransport(scope: scope)
            await service.overrideManifest(NoteSyncManifest(protocolVersion: 2, complete: true, notes: kind == .delete ? [.init(assetID: "old-remote", syncToken: "old-base", lifecycle: .active)] : []))
            let sync = try NoteSyncCoordinator(store: store, service: service)
            await sync.resume(); await sync.synchronize()
            let saved = try await store.note(localID: text.localID)
            XCTAssertTrue(saved?.isSynchronized == true)
            let blocked = try await store.note(localID: retained.localID)
            XCTAssertEqual(blocked?.pendingOperation, pending)
            XCTAssertEqual(blocked?.syncIssue, "unsupported_operation")
            let status = await sync.status
            XCTAssertEqual(status, .idle)
            let later = try await store.create(body: body("later eligible text"))
            await sync.synchronize()
            let laterSaved = try await store.note(localID: later.localID)
            XCTAssertTrue(laterSaved?.isSynchronized == true)
            let stillBlocked = try await store.note(localID: retained.localID)
            XCTAssertEqual(stillBlocked?.pendingOperation, pending)
            let operations = await service.operations
            XCTAssertEqual(operations.count, 2)
            XCTAssertTrue(operations.allSatisfy { $0.kind == .create })
            await sync.suspend(); try await store.close()
        }
    }

    func testTextOnlyProtocolSendsTextWithoutUploadingImageDrafts() async throws {
        let store = try await open()
        let text = try await store.create(body: body("M1 text"))
        let raw = #"{"editor_kind":"blocknote","schema_version":1,"blocks":[{"id":"image","type":"image","props":{"mediaRef":"local-note-attachment:retained"},"children":[]}]}"#
        let image = try await store.create(body: OfflineNoteBody(content: "image draft", contentJSON: raw))
        let service = NoteSyncTestTransport(scope: scope)
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 2, complete: true, notes: []))
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let saved = try await store.note(localID: text.localID)
        XCTAssertTrue(saved?.isSynchronized == true)
        let kept = try await store.note(localID: image.localID)
        XCTAssertEqual(kept?.body.contentJSON, raw)
        XCTAssertEqual(kept?.syncIssue, "unsupported_document")
        let requests = await service.operations
        XCTAssertEqual(requests.count, 1)
        let uploads = await service.uploadIDs
        XCTAssertTrue(uploads.isEmpty)
        await coordinator.suspend(); try await store.close()
    }

    func testTextOnlyProtocolAcceptsEditorBlockArrayWithoutRewritingLocalBytes() async throws {
        let store = try await open()
        let raw = #"[{"id":"paragraph","type":"paragraph","props":{"textAlignment":"left"},"content":[{"type":"text","text":"Native editor","styles":{}}],"children":[]}]"#
        let note = try await store.create(body: OfflineNoteBody(content: "Native editor", contentJSON: raw))
        let service = NoteSyncTestTransport(scope: scope)
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 2, complete: true, notes: []))
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let saved = try await store.note(localID: note.localID)
        XCTAssertTrue(saved?.isSynchronized == true)
        XCTAssertEqual(saved?.body.contentJSON, raw)
        let operations = await service.operations
        let payload = try XCTUnwrap(operations.first)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload.requestBody) as? [String: Any])
        let wire = try XCTUnwrap(json["content_json"] as? String)
        let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(wire.utf8)) as? [String: Any])
        XCTAssertEqual(document["blocks"] as? NSArray, try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? NSArray)
        await coordinator.suspend(); try await store.close()
    }

    func testTextOnlyProtocolKeepsPendingLifecycleForLaterWithoutSending() async throws {
        let store = try await open()
        let remote = NoteSyncTestTransport.snapshot("remote", token: "base", text: "keep")
        let note = try unwrap(try await store.applyRemote(remote, localID: nil, expectedGeneration: nil))
        _ = try await store.setLifecycle(localID: note.localID, lifecycle: .trashed)
        let service = NoteSyncTestTransport(scope: scope)
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 2, complete: true, notes: [.init(assetID: "remote", syncToken: "base", lifecycle: .active)]))
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let requests = await service.operations
        XCTAssertTrue(requests.isEmpty)
        let retained = try await store.note(localID: note.localID)
        XCTAssertEqual(retained?.desiredLifecycle, .trashed)
        XCTAssertEqual(retained?.body.content, "keep")
        await coordinator.suspend(); try await store.close()
    }

    func testFreezeBeforeHTTPAndLostAcknowledgmentReplaysExactBytesAfterRestart() async throws {
        let store = try await open()
        let note = try await store.create(body: body("first"))
        let service = NoteSyncTestTransport(scope: scope)
        await service.setSendHook { operation in
            let stored = try await store.note(localID: note.localID)
            XCTAssertEqual(stored?.pendingOperation?.requestBody, operation.requestBody)
            XCTAssertEqual(stored?.pendingOperation?.operationID, operation.operationID)
        }
        await service.loseNextAcknowledgment()
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume()
        await coordinator.synchronize()
        let frozen = try unwrap(try await store.note(localID: note.localID)?.pendingOperation)
        _ = try await store.saveBody(localID: note.localID, body: body("later"))
        await coordinator.suspend()
        try await store.close()

        let reopened = try await open()
        await service.setSendHook(nil)
        let restarted = try NoteSyncCoordinator(store: reopened, service: service)
        await restarted.resume()
        await restarted.synchronize(forceRetry: true)
        let requests = await service.operations
        XCTAssertGreaterThanOrEqual(requests.count, 2)
        XCTAssertEqual(requests[0].operationID, requests[1].operationID)
        XCTAssertEqual(frozen.requestBody, requests[1].requestBody)
        let saved = try unwrap(try await reopened.note(localID: note.localID))
        XCTAssertEqual(saved.body.content, "later")
        XCTAssertEqual(saved.localID, note.localID)
        XCTAssertTrue(saved.isSynchronized)
        let commits = await service.commitCount
        XCTAssertEqual(commits, 2)
        try await reopened.close()
    }

    func testOldAcknowledgmentDoesNotReplaceNewerEditAndNextOperationUsesReceiptBaseline() async throws {
        let store = try await open(); let note = try await store.create(body: body("first"))
        let service = NoteSyncTestTransport(scope: scope)
        let newerBody = body("newer")
        await service.setSendHook { operation in
            if operation.kind == .create { _ = try await store.saveBody(localID: note.localID, body: newerBody) }
        }
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let saved = try unwrap(try await store.note(localID: note.localID))
        let requests = await service.operations
        XCTAssertEqual(requests.map(\.kind), [.create, .update])
        XCTAssertEqual(requests[1].baseSyncToken, "token-1")
        XCTAssertEqual(saved.body.content, "newer")
        XCTAssertTrue(saved.isSynchronized)
        try await store.close()
    }

    func testDefinitiveRejectionOfOlderBodyDoesNotBlockAnAlreadyCorrectedDraft() async throws {
        for failure in [NoteSyncFailure.unsupportedDocument, .validation] {
            let store = try await open()
            let note = try await store.create(body: body("unsupported old body"))
            let service = NoteSyncTestTransport(scope: scope)
            await service.failContent("unsupported old body", with: failure)
            let correctedBody = body("corrected body")
            await service.setSendHook { _ in
                _ = try await store.saveBody(localID: note.localID, body: correctedBody)
            }
            let coordinator = try NoteSyncCoordinator(store: store, service: service)
            await coordinator.resume(); await coordinator.synchronize()
            let corrected = try unwrap(try await store.note(localID: note.localID))
            XCTAssertNil(corrected.syncIssue)
            XCTAssertNil(corrected.pendingOperation)
            await service.setSendHook(nil)
            await coordinator.synchronize(forceRetry: true)
            let uploaded = try unwrap(try await store.note(localID: note.localID))
            XCTAssertTrue(uploaded.isSynchronized)
            XCTAssertEqual(uploaded.body.content, "corrected body")
            await coordinator.suspend(); try await store.close()
        }
    }

    func testUnreadyAndTruncatedManifestNeverUploadOrInterpretEmptyLibrary() async throws {
        for manifest in [NoteSyncManifest(protocolVersion: 0, complete: true, notes: []), NoteSyncManifest(protocolVersion: 1, complete: false, notes: [])] {
            let store = try await open()
            let note = try await store.create(body: body("kept"))
            let service = NoteSyncTestTransport(scope: scope); await service.overrideManifest(manifest)
            let coordinator = try NoteSyncCoordinator(store: store, service: service)
            await coordinator.resume(); await coordinator.synchronize()
            let requests = await service.operations; XCTAssertTrue(requests.isEmpty)
            let status = await coordinator.status; XCTAssertEqual(status, .notReady)
            let retained = try await store.note(localID: note.localID); XCTAssertNotNil(retained)
            try await store.close()
        }
    }

    func testDeleteSuppressesUnsentBodyAndRestoreAcknowledgesOnlyLifecycle() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let remote = NoteSyncTestTransport.snapshot("asset-public", token: "original", text: "published", isPublic: true)
        await service.setRemote(remote)
        let local = try unwrap(try await store.applyRemote(remote, localID: nil, expectedGeneration: nil))
        _ = try await store.saveBody(localID: local.localID, body: body("private revision"))
        _ = try await store.setLifecycle(localID: local.localID, lifecycle: .trashed)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let deleted = try unwrap(try await store.note(localID: local.localID))
        XCTAssertTrue(deleted.hasUnacknowledgedBody); XCTAssertEqual(deleted.confirmedLifecycle, .trashed)
        let firstRequests = await service.operations; XCTAssertEqual(firstRequests.map(\.kind), [.delete])
        _ = try await store.setLifecycle(localID: local.localID, lifecycle: .active)
        await coordinator.synchronize()
        let requests = await service.operations; XCTAssertEqual(requests.map(\.kind), [.delete, .restore, .update])
        let final = try unwrap(try await store.note(localID: local.localID))
        XCTAssertTrue(final.isSynchronized); XCTAssertTrue(final.isPublic)
        XCTAssertEqual(final.body.content, "private revision")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: requests.last!.requestBody) as? [String: Any])
        XCTAssertNil(payload["is_public"])
        try await store.close()
    }

    func testTransientFailurePersistsBackoffAndDoesNotBlockAnotherNote() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let one = try await store.create(body: body("one")); _ = try await store.create(body: body("two"))
        await service.failContent("one", with: .transient(retryAfter: 120))
        let now = Date(timeIntervalSince1970: 1000)
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { now }, jitter: { 0 })
        await coordinator.resume(); await coordinator.synchronize()
        let failed = try unwrap(try await store.note(localID: one.localID))
        XCTAssertEqual(failed.pendingOperation?.attemptCount, 1)
        XCTAssertEqual(failed.pendingOperation?.nextAttemptAt, now.addingTimeInterval(120))
        let all = try await store.notes(); XCTAssertEqual(all.filter(\.isSynchronized).count, 1)
        let before = await service.operations.count
        await coordinator.synchronize()
        let after = await service.operations.count; XCTAssertEqual(after, before)
        try await store.close()
    }

    func testManifestRetryAfterSurvivesEditsRefreshAndForegroundUntilTheDraftCanSend() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let local = try await store.create(body: body("first"))
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await service.failManifest(.transient(retryAfter: 60))
        await coordinator.resume()
        await coordinator.localDidChange(localID: local.localID)
        clock.advance(2)
        await coordinator.synchronize()

        _ = try await store.saveBody(localID: local.localID, body: body("latest draft"))
        await coordinator.localDidChange(localID: local.localID)
        await coordinator.synchronize(forceRetry: true)
        await coordinator.suspend()
        await coordinator.resume()
        clock.advance(59)
        await coordinator.synchronize()
        // The old edit deadline has expired. Give the real foreground timer
        // several opportunities to reveal a tight automatic retry loop.
        try await Task.sleep(nanoseconds: 250_000_000)
        let attempts = await service.manifestCalls
        XCTAssertEqual(attempts, 1)
        let status = await coordinator.status
        XCTAssertEqual(status, .waitingForNetwork)
        let retained = try unwrap(try await store.note(localID: local.localID))
        XCTAssertTrue(retained.hasUnacknowledgedBody)
        XCTAssertEqual(retained.body.content, "latest draft")

        await service.failManifest(nil)
        clock.advance(1)
        await coordinator.synchronize()
        let synced = try unwrap(try await store.note(localID: local.localID))
        XCTAssertTrue(synced.isSynchronized)
        XCTAssertEqual(synced.body.content, "latest draft")
        let sent = await service.operations
        XCTAssertEqual(sent.count, 1)
        await coordinator.suspend(); try await store.close()
    }

    func testUnreadyManifestResponsesBackOffUntilReadinessRecovers() async throws {
        for incomplete in [false, true] {
            let store = try await NoteLocalStore.open(rootURL: root.appendingPathComponent(UUID().uuidString), scope: scope)
            let service = NoteSyncTestTransport(scope: scope)
            let clock = NoteSyncTestClock()
            let local = try await store.create(body: body("kept"))
            if incomplete {
                await service.overrideManifest(.init(protocolVersion: 3, complete: false, notes: []))
            } else {
                await service.failManifest(.notReady)
            }
            let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
            await coordinator.resume()
            await coordinator.localDidChange(localID: local.localID)
            clock.advance(2)
            await coordinator.synchronize()
            clock.advance(1)
            await coordinator.synchronize()
            let first = await service.manifestCalls
            XCTAssertEqual(first, 1)
            clock.advance(1)
            await coordinator.synchronize()
            clock.advance(3)
            await coordinator.synchronize()
            let second = await service.manifestCalls
            XCTAssertEqual(second, 2)
            let status = await coordinator.status
            XCTAssertEqual(status, .notReady)

            await service.failManifest(nil)
            await service.overrideManifest(.init(protocolVersion: 3, complete: true, notes: []))
            clock.advance(1)
            await coordinator.synchronize()
            let synced = try unwrap(try await store.note(localID: local.localID))
            XCTAssertTrue(synced.isSynchronized)
            await coordinator.suspend(); try await store.close()
        }
    }

    func testBootstrapRetryAfterDefersTheNextRecentPageAndManifest() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let remote = NoteSyncTestTransport.snapshot("remote", token: "v1", text: "cloud")
        await service.setRemote(remote)
        await service.setPageHandler { _ in throw NoteSyncFailure.transient(retryAfter: 90) }
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await coordinator.resume()
        await coordinator.synchronize()
        clock.advance(89)
        await coordinator.synchronize(forceRetry: true)
        let pages = await service.pageCalls
        let manifests = await service.manifestCalls
        XCTAssertEqual(pages, 1)
        XCTAssertEqual(manifests, 0)

        await service.setPageHandler { _ in [remote] }
        clock.advance(1)
        await coordinator.synchronize()
        let notes = try await store.notes()
        XCTAssertEqual(notes.map(\.serverAssetID), ["remote"])
        await coordinator.suspend(); try await store.close()
    }

    func testIsolatedFailedBackfillPageWaitsBeforeAnOrdinaryRetry() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let known = NoteSyncTestTransport.snapshot("recent", token: "v1", text: "recent")
        let older = NoteSyncTestTransport.snapshot("older", token: "v1", text: "older")
        _ = try await store.applyRemote(known, localID: nil, expectedGeneration: nil)
        await service.setRemote(known)
        await service.setRemote(older)
        await service.setPageHandler { _ in throw NoteSyncFailure.transient(retryAfter: nil) }
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await coordinator.resume()
        await coordinator.synchronize()
        clock.advance(1)
        await coordinator.synchronize()
        let attempts = await service.pageCalls
        XCTAssertEqual(attempts, 1)
        let retained = try await store.notes()
        XCTAssertEqual(retained.map(\.serverAssetID), ["recent"])

        await service.setPageHandler { _ in [older] }
        clock.advance(1)
        await coordinator.synchronize()
        let all = try await store.notes()
        XCTAssertEqual(Set(all.compactMap(\.serverAssetID)), ["recent", "older"])
        await coordinator.suspend(); try await store.close()
    }

    func testManifestRecoversAutomaticallyWhenTheSessionRetryIsDue() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let note = try await store.create(body: body("offline draft"))
        await service.failManifest(.transient(retryAfter: nil))
        let sent = expectation(description: "foreground timer retries the pending draft")
        await service.setSendHook { _ in sent.fulfill() }
        let coordinator = try NoteSyncCoordinator(store: store, service: service, jitter: { 0 })
        await coordinator.resume()
        await coordinator.synchronize()
        await service.failManifest(nil)
        await fulfillment(of: [sent], timeout: 5)
        await coordinator.synchronize()
        let saved = try unwrap(try await store.note(localID: note.localID))
        XCTAssertTrue(saved.isSynchronized)
        await coordinator.suspend(); try await store.close()
    }

    func testDetailRetryAfterStopsRemainingReadsAndResumesAtTheDeadline() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        for id in ["one", "two", "three"] {
            await service.setRemote(NoteSyncTestTransport.snapshot(id, token: "v1", text: id))
        }
        await service.setDetailHook { _ in throw NoteSyncFailure.transient(retryAfter: 75) }
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await coordinator.resume()
        await coordinator.synchronize()
        clock.advance(74)
        await coordinator.synchronize()
        let reads = await service.detailIDs
        let manifests = await service.manifestCalls
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(manifests, 1)

        await service.setDetailHook(nil)
        clock.advance(1)
        await coordinator.synchronize()
        let notes = try await store.notes()
        XCTAssertEqual(notes.count, 3)
        await coordinator.suspend(); try await store.close()
    }

    func testEditDuringFrozenRetryDoesNotPollManifestBeforeTheOperationIsDue() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let note = try await store.create(body: body("first"))
        await service.failNextSend(.transient(retryAfter: 60))
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await coordinator.resume()
        await coordinator.synchronize()
        _ = try await store.saveBody(localID: note.localID, body: body("next edit"))
        await coordinator.localDidChange(localID: note.localID)
        clock.advance(2)
        await coordinator.synchronize()
        let beforeTimer = await service.manifestCalls
        try await Task.sleep(nanoseconds: 250_000_000)
        let afterTimer = await service.manifestCalls
        XCTAssertEqual(afterTimer, beforeTimer)
        let beforeRetry = await service.operations
        XCTAssertEqual(beforeRetry.count, 1)

        clock.advance(58)
        await coordinator.synchronize()
        let saved = try unwrap(try await store.note(localID: note.localID))
        XCTAssertTrue(saved.isSynchronized)
        XCTAssertEqual(saved.body.content, "next edit")
        let sent = await service.operations
        XCTAssertEqual(sent.map(\.kind), [.create, .create, .update])
        XCTAssertEqual(sent.first?.operationID, sent[1].operationID)
        await coordinator.suspend(); try await store.close()
    }

    func testLaterAttachmentWithAnExpiredRetryCannotWakeAheadOfTheFirstUpload() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let existing = try await makeImageNote(store)
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let added = try files.retain(data: Data([5, 6]), filename: "next.png", mimeType: "image/png")
        let attachments = existing.attachments + [added]
        let blocks = attachments.map { ["type": "image", "props": ["mediaRef": NoteSyncPayload.localMediaRef(uploadID: $0.uploadID)]] }
        let json = try JSONSerialization.data(withJSONObject: ["blocks": blocks])
        let note = try await store.saveBody(localID: existing.localID,
            body: .init(content: "two images", contentJSON: String(decoding: json, as: UTF8.self)), attachments: attachments)
        try await store.recordUploadRetry(localID: note.localID, uploadID: attachments[0].uploadID,
                                          nextAttemptAt: clock.read().addingTimeInterval(60))
        try await store.recordUploadRetry(localID: note.localID, uploadID: added.uploadID, nextAttemptAt: clock.read())
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await coordinator.resume()
        await coordinator.synchronize()
        try await Task.sleep(nanoseconds: 250_000_000)
        let manifests = await service.manifestCalls
        XCTAssertEqual(manifests, 1)
        clock.advance(60)
        await coordinator.synchronize()
        let saved = try unwrap(try await store.note(localID: note.localID))
        XCTAssertTrue(saved.isSynchronized)
        let uploads = await service.uploadIDs
        XCTAssertEqual(uploads, attachments.map(\.uploadID))
        await coordinator.suspend(); try await store.close()
    }

    func testUnchangedCommittedBodyDoesNotLeaveAnExpiredEditWakeup() async throws {
        let store = try await open()
        let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let remote = NoteSyncTestTransport.snapshot("one", token: "v1", text: "unchanged")
        await service.setRemote(remote)
        let local = try unwrap(try await store.applyRemote(remote, localID: nil, expectedGeneration: nil))
        _ = try await store.saveBody(localID: local.localID, body: local.body)
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() })
        await coordinator.resume()
        await coordinator.localDidChange(localID: local.localID)
        clock.advance(2)
        await coordinator.synchronize()
        try await Task.sleep(nanoseconds: 250_000_000)
        let manifests = await service.manifestCalls
        XCTAssertEqual(manifests, 1)
        let sent = await service.operations
        XCTAssertTrue(sent.isEmpty)
        await coordinator.suspend(); try await store.close()
    }

    func testStaleVersionRetainsBothBodiesAndExplicitCloudChoiceResolves() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let original = NoteSyncTestTransport.snapshot("remote", token: "base", text: "old")
        let local = try unwrap(try await store.applyRemote(original, localID: nil, expectedGeneration: nil))
        _ = try await store.saveBody(localID: local.localID, body: body("local"))
        await service.setRemote(NoteSyncTestTransport.snapshot("remote", token: "web", text: "web changed"))
        await service.failContent("local", with: .staleVersion)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let conflict = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(conflict.body.content, "local"); XCTAssertEqual(conflict.remoteSnapshot?.body.content, "web changed")
        XCTAssertNil(conflict.pendingOperation)
        try await coordinator.useCloudVersion(localID: local.localID)
        let resolved = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(resolved.body.content, "web changed"); XCTAssertTrue(resolved.isSynchronized)
        try await store.close()
    }

    func testLateResponseAfterSuspendCannotAcknowledgeOrCrossScope() async throws {
        let store = try await open(); let note = try await store.create(body: body("original account"))
        let service = NoteSyncTestTransport(scope: scope); let gate = NoteSyncTestGate()
        await service.setSendHook { _ in await gate.wait() }
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume()
        let work = Task { await coordinator.synchronize() }
        await gate.started()
        await coordinator.suspend()
        await gate.release(); await work.value
        let retained = try unwrap(try await store.note(localID: note.localID))
        XCTAssertNotNil(retained.pendingOperation); XCTAssertNil(retained.serverAssetID)
        let foreign = NoteSyncTestTransport(scope: NoteStoreScope(actorID: "other", environmentID: "local"))
        XCTAssertThrowsError(try NoteSyncCoordinator(store: store, service: foreign))
        try await store.close()
    }

    func testManifestPullUsesGenerationFenceAndDownloadsOnlyChangedNotes() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let original = NoteSyncTestTransport.snapshot("remote", token: "base", text: "old")
        let local = try unwrap(try await store.applyRemote(original, localID: nil, expectedGeneration: nil))
        await service.setRemote(NoteSyncTestTransport.snapshot("remote", token: "new", text: "remote new"))
        let typedBody = body("typed during pull")
        await service.setDetailHook { _ in _ = try await store.saveBody(localID: local.localID, body: typedBody) }
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let retained = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(retained.body.content, "typed during pull"); XCTAssertEqual(retained.baseSyncToken, "base")
        await service.setDetailHook(nil)
        // A clean library with unchanged tokens needs no detail requests.
        let secondRoot = root.appendingPathComponent("large")
        let large = try await NoteLocalStore.open(rootURL: secondRoot, scope: scope)
        let largeService = NoteSyncTestTransport(scope: scope)
        for i in 0..<1000 {
            let item = NoteSyncTestTransport.snapshot("note-\(i)", token: "v1-\(i)", text: "body")
            _ = try await large.applyRemote(item, localID: nil, expectedGeneration: nil); await largeService.setRemote(item)
        }
        let largeCoordinator = try NoteSyncCoordinator(store: large, service: largeService)
        await largeCoordinator.resume(); await largeCoordinator.synchronize(); await largeCoordinator.synchronize()
        let details = await largeService.detailIDs; XCTAssertTrue(details.isEmpty)
        try await store.close(); try await large.close()
    }

    func testCleanMissingNoteBecomesReadableAgainOnlyAfterCompleteAuthorizedManifest() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let snapshot = NoteSyncTestTransport.snapshot("remote", token: "v1", text: "retained")
        let local = try unwrap(try await store.applyRemote(snapshot, localID: nil, expectedGeneration: nil))
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let missing = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(missing.syncIssue, "remote_unavailable"); XCTAssertEqual(missing.body.content, "retained")
        await service.setRemote(snapshot); await coordinator.synchronize()
        let restored = try unwrap(try await store.note(localID: local.localID))
        XCTAssertTrue(restored.isSynchronized); XCTAssertNil(restored.syncIssue)
        try await store.close()
    }

    func testHTTPFailureClassesNeverFallBackOrDropFrozenIdentity() async throws {
        for failure in [NoteSyncFailure.authenticationRequired, .permissionDenied, .accountRestricted, .preconditionRequired, .idempotencyConflict] {
            let store = try await NoteLocalStore.open(rootURL: root.appendingPathComponent(UUID().uuidString), scope: scope)
            let local = try await store.create(body: body("blocked")); let service = NoteSyncTestTransport(scope: scope)
            await service.failContent("blocked", with: failure)
            let coordinator = try NoteSyncCoordinator(store: store, service: service)
            await coordinator.resume(); await coordinator.synchronize(); await coordinator.synchronize()
            let saved = try unwrap(try await store.note(localID: local.localID))
            XCTAssertNotNil(saved.pendingOperation); XCTAssertEqual(saved.body.content, "blocked")
            let sent = await service.operations; XCTAssertEqual(sent.count, 1)
            await coordinator.suspend(); try await store.close()
        }
    }

    func testUnsupportedDocumentKeepsEveryByteAndDoesNotBlockOtherNotes() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let raw = #"{ "schema_version":1,"editor_kind":"blocknote","blocks":[{"id":"x","type":"mindmap","props":{"future":{"lossless":[1,2,3]}}}] }"#
        let local = try await store.create(body: OfflineNoteBody(content: "unsupported", contentJSON: raw))
        _ = try await store.create(body: body("supported"))
        await service.failContent("unsupported", with: .unsupportedDocument)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize(); await coordinator.synchronize()
        let saved = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(saved.body.contentJSON, raw); XCTAssertEqual(saved.syncIssue, "unsupported_document")
        XCTAssertNil(saved.pendingOperation); XCTAssertFalse(saved.isSynchronized)
        let notes = try await store.notes(); XCTAssertEqual(notes.filter(\.isSynchronized).count, 1)
        await coordinator.suspend(); try await store.close()
    }

    func testDefinitiveAuthorityRevocationClosesOnlyRejectedOperationAndPreservesDraft() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let local = try await store.create(body: body("revoked draft"))
        await service.failContent("revoked draft", with: .authorityRevoked)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize(); await coordinator.synchronize()
        let retained = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(retained.body.content, "revoked draft")
        XCTAssertEqual(retained.syncIssue, "permission_denied")
        XCTAssertNil(retained.pendingOperation); XCTAssertFalse(retained.isSynchronized)
        let requests = await service.operations; XCTAssertEqual(requests.count, 1)
        await coordinator.suspend(); try await store.close()
    }

    func testMalformedDocumentIsBlockedInsteadOfRetriedAsNetworkFailure() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let local = try await store.create(body: OfflineNoteBody(content: "retained", contentJSON: "{ broken"))
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let saved = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(saved.body.contentJSON, "{ broken"); XCTAssertEqual(saved.syncIssue, "unsupported_document")
        let sent = await service.operations; XCTAssertTrue(sent.isEmpty)
        await coordinator.suspend(); try await store.close()
    }

    func testConflictSaveAsCreatesPrivateIdentityAndLeavesRemoteBodyUntouched() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let remote = NoteSyncTestTransport.snapshot("remote", token: "v1", text: "old", isPublic: true)
        let local = try unwrap(try await store.applyRemote(remote, localID: nil, expectedGeneration: nil))
        _ = try await store.saveBody(localID: local.localID, body: body("my copy"))
        let changed = NoteSyncTestTransport.snapshot("remote", token: "v2", text: "web new", isPublic: true)
        let dirty = try unwrap(try await store.note(localID: local.localID))
        _ = try await store.applyRemote(changed, localID: local.localID, expectedGeneration: dirty.generation)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        let copy = try await coordinator.saveLocalAsNewNote(localID: local.localID)
        XCTAssertNotEqual(copy.localID, local.localID); XCTAssertNil(copy.serverAssetID); XCTAssertFalse(copy.isPublic)
        XCTAssertEqual(copy.body.content, "my copy"); XCTAssertNil(copy.baseSyncToken)
        let original = try unwrap(try await store.note(localID: local.localID))
        XCTAssertEqual(original.body.content, "web new"); XCTAssertTrue(original.isPublic)
        XCTAssertTrue(original.isSynchronized)
        try await store.close()
    }

    func testCloudWriteCoalescesTwoSecondIdleAndThirtySecondMaximum() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let clock = NoteSyncTestClock()
        let local = try await store.create(body: body("first"))
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() })
        await coordinator.resume(); await coordinator.localDidChange(localID: local.localID)
        clock.advance(1); await coordinator.synchronize()
        let early = await service.operations; XCTAssertTrue(early.isEmpty)
        clock.advance(1); await coordinator.synchronize()
        let afterIdle = await service.operations; XCTAssertEqual(afterIdle.count, 1)
        for i in 0..<31 {
            _ = try await store.saveBody(localID: local.localID, body: body("typing-\(i)"))
            await coordinator.localDidChange(localID: local.localID)
            await coordinator.synchronize()
            clock.advance(1)
        }
        let afterContinuous = await service.operations; XCTAssertEqual(afterContinuous.count, 2)
        await coordinator.suspend(); try await store.close()
    }

    func testCreationWithUnknownResultThenDeleteResolvesCreateBeforeLifecycle() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let local = try await store.create(body: body("original"))
        await service.loseNextAcknowledgment()
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        _ = try await store.saveBody(localID: local.localID, body: body("never publish this"))
        _ = try await store.setLifecycle(localID: local.localID, lifecycle: .trashed)
        await coordinator.synchronize(forceRetry: true)
        let operations = await service.operations
        XCTAssertEqual(operations.map(\.kind), [.create, .create, .delete])
        XCTAssertEqual(operations[0].operationID, operations[1].operationID)
        let saved = try unwrap(try await store.note(localID: local.localID))
        XCTAssertTrue(saved.hasUnacknowledgedBody); XCTAssertEqual(saved.confirmedLifecycle, .trashed)
        XCTAssertEqual(saved.body.content, "never publish this")
        await coordinator.suspend(); try await store.close()
    }

    private func makeImageNote(_ store: NoteLocalStore) async throws -> OfflineNote {
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let attachment = try files.retain(data: Data([1,2,3,4]), filename: "photo.png", mimeType: "image/png")
        let raw = #"{"schema_version":1,"editor_kind":"blocknote","blocks":[{"id":"image-1","type":"image","props":{"mediaRef":"REF","url":"file:///local/photo.png","caption":"keep caption"},"content":[],"children":[]}]}"#.replacingOccurrences(of: "REF", with: NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID))
        let note = try await store.create(body: body("image"))
        return try await store.saveBody(localID: note.localID, body: OfflineNoteBody(content: "image", contentJSON: raw), attachments: [attachment])
    }

    func testNativeImageMarkdownPreviewIsLocalOnlyWhileItsCaptionAndBodyRemain() async throws {
        let store = try await open()
        let note = try await makeImageNote(store)
        let attachment = note.attachments[0]
        let url = try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID).absoluteString
        let markdown = "Keep text\n\n![Inline image](\(url))\n"
        var document = try unwrap(JSONSerialization.jsonObject(with: Data(note.body.contentJSON!.utf8)) as? [String: Any])
        document["content"] = markdown
        let savedBody = OfflineNoteBody(content: markdown, contentJSON: String(decoding: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]), as: UTF8.self))
        _ = try await store.saveBody(localID: note.localID, body: savedBody)
        try await store.acknowledgeUpload(localID: note.localID, uploadID: attachment.uploadID,
            receipt: .init(mediaRef: "med_aaaaaaaaaaaaaaaa", sha256: attachment.sha256, mimeType: attachment.mimeType, byteCount: attachment.byteCount))
        let retained = try unwrap(try await store.note(localID: note.localID))
        let operation = try unwrap(NoteSyncPayload.operation(for: retained, operationID: "native-image-content"))
        let payload = try unwrap(JSONSerialization.jsonObject(with: operation.requestBody) as? [String: Any])
        XCTAssertEqual(payload["content"] as? String, "Keep text\n\nInline image\n")
        let wire = String(decoding: operation.requestBody, as: UTF8.self)
        XCTAssertFalse(wire.contains("chorai-note-media:"))
        XCTAssertTrue(wire.contains("med_aaaaaaaaaaaaaaaa"))
        XCTAssertEqual(retained.body, savedBody)
        try await store.close()
    }

    func testUploadResponseLossRetainsIdentityAndDoesNotFreezeUnresolvedImage() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let local = try await makeImageNote(store)
        await service.loseNextUploadAcknowledgment()
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let pending = try unwrap(try await store.note(localID: local.localID))
        XCTAssertNil(pending.pendingOperation); XCTAssertNil(pending.attachments.first?.mediaRef)
        await coordinator.suspend(); try await store.close()
        let reopened = try await open(); let next = try NoteSyncCoordinator(store: reopened, service: service)
        await next.resume(); await next.synchronize(forceRetry: true)
        let uploads = await service.uploadIDs; XCTAssertEqual(uploads, [local.attachments[0].uploadID, local.attachments[0].uploadID])
        let requests = await service.operations; XCTAssertEqual(requests.count, 1)
        let json = String(decoding: requests[0].requestBody, as: UTF8.self)
        XCTAssertFalse(json.contains("file:")); XCTAssertFalse(json.contains("local-note-attachment:")); XCTAssertTrue(json.contains("keep caption"))
        let saved = try unwrap(try await reopened.note(localID: local.localID)); XCTAssertTrue(saved.isSynchronized)
        XCTAssertEqual(saved.body.contentJSON, local.body.contentJSON)
        await next.suspend(); try await reopened.close()
    }

    func testImageAddedWhileFinalUploadIsSuspendedUploadsBeforeFreezingTheNewBody() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        await service.overrideManifest(NoteSyncManifest(protocolVersion: 3, complete: true, notes: []))
        let note = try await makeImageNote(store)
        let gate = NoteSyncTestGate()
        await service.setUploadHook { attachment in
            if attachment.uploadID == note.attachments[0].uploadID { await gate.wait() }
        }
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        let delivery = Task { await coordinator.resume(); await coordinator.synchronize(forceRetry: true) }
        await gate.started()
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let added = try files.retain(data: Data([5, 6]), filename: "second.png", mimeType: "image/png")
        var document = try unwrap(JSONSerialization.jsonObject(with: Data(note.body.contentJSON!.utf8)) as? [String: Any])
        var blocks = try unwrap(document["blocks"] as? [[String: Any]])
        blocks.append(["id":"image-2", "type":"image", "props":["mediaRef":NoteSyncPayload.localMediaRef(uploadID: added.uploadID)], "children":[]])
        document["blocks"] = blocks
        let changed = OfflineNoteBody(content: "two images", contentJSON: String(decoding: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]), as: UTF8.self))
        _ = try await store.saveBody(localID: note.localID, body: changed, attachments: note.attachments + [added])
        await gate.release(); await delivery.value
        let saved = try unwrap(try await store.note(localID: note.localID))
        XCTAssertNil(saved.syncIssue)
        XCTAssertTrue(saved.isSynchronized)
        XCTAssertEqual(saved.body, changed)
        let uploads = await service.uploadIDs
        XCTAssertEqual(uploads, [note.attachments[0].uploadID, added.uploadID])
        let operations = await service.operations
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attachments.count, 2)
        await coordinator.suspend(); try await store.close()
    }

    func testExpiredImageRecoveryKeepsFrozenNoteBytesAndIdentity() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let local = try await makeImageNote(store)
        await service.failNextSend(.mediaExpired)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let pending = try unwrap(try await store.note(localID: local.localID)?.pendingOperation)
        XCTAssertEqual(pending.attemptCount, 1)
        await coordinator.synchronize(forceRetry: true)
        let requests = await service.operations
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[0].requestBody, requests[1].requestBody)
        XCTAssertEqual(requests[0].operationID, requests[1].operationID)
        let uploads = await service.uploadIDs; XCTAssertEqual(uploads.count, 2); XCTAssertEqual(uploads[0], uploads[1])
        let saved = try unwrap(try await store.note(localID: local.localID)); XCTAssertTrue(saved.isSynchronized)
        await coordinator.suspend(); try await store.close()
    }

    func testCommittedImageReplayDoesNotRequireAnotherUpload() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        _ = try await makeImageNote(store); await service.loseNextAcknowledgment()
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize(); await coordinator.synchronize(forceRetry: true)
        let uploads = await service.uploadIDs; XCTAssertEqual(uploads.count, 1)
        let commits = await service.commitCount; XCTAssertEqual(commits, 1)
        await coordinator.suspend(); try await store.close()
    }

    func testRemovedImageDoesNotUploadOrBlockTextSynchronization() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let image = try await makeImageNote(store)
        _ = try await store.saveBody(localID: image.localID, body: body("image removed"))
        await service.failUploads(.permissionDenied, startingAt: 1)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let uploads = await service.uploadIDs; XCTAssertTrue(uploads.isEmpty)
        let operations = await service.operations; XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attachments.count, 0)
        let saved = try unwrap(try await store.note(localID: image.localID))
        XCTAssertTrue(saved.isSynchronized); XCTAssertEqual(saved.attachments, image.attachments)
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        XCTAssertEqual(try files.read(image.attachments[0]), Data([1,2,3,4]))
        await coordinator.suspend(); try await store.close()
    }

    func testFrozenImageRequestContainsOnlyReferencedAttachments() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let image = try await makeImageNote(store)
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let unused = try files.retain(data: Data([8,9]), filename: "unused.png", mimeType: "image/png")
        _ = try await store.saveBody(localID: image.localID, body: image.body, attachments: image.attachments + [unused])
        await service.failUploads(.permissionDenied, startingAt: 2)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let uploads = await service.uploadIDs; XCTAssertEqual(uploads, [image.attachments[0].uploadID])
        let operations = await service.operations; XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.attachments.map(\.uploadID), image.attachments.map(\.uploadID))
        let saved = try unwrap(try await store.note(localID: image.localID))
        XCTAssertTrue(saved.isSynchronized); XCTAssertEqual(saved.attachments.count, 2)
        await coordinator.suspend(); try await store.close()
    }

    func testAttachmentPlaceholderWaitsForAnActualEditorSave() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let placeholder = try await store.create(body: OfflineNoteBody(content: ""))
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let before = await service.operations; XCTAssertTrue(before.isEmpty)
        _ = try await store.saveBody(localID: placeholder.localID, body: body("first saved edit"))
        await coordinator.synchronize()
        let after = await service.operations; XCTAssertEqual(after.count, 1)
        let saved = try unwrap(try await store.note(localID: placeholder.localID))
        XCTAssertTrue(saved.isSynchronized)
        await coordinator.suspend(); try await store.close()
    }

    func testUploadRetryAfterSurvivesProcessRestart() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope); let clock = NoteSyncTestClock()
        let local = try await makeImageNote(store)
        await service.failUploads(.transient(retryAfter: 120), startingAt: 1)
        let coordinator = try NoteSyncCoordinator(store: store, service: service, now: { clock.read() }, jitter: { 0 })
        await coordinator.resume(); await coordinator.synchronize(); await coordinator.suspend(); try await store.close()
        let reopened = try await open(); let next = try NoteSyncCoordinator(store: reopened, service: service, now: { clock.read() }, jitter: { 0 })
        await next.resume(); await next.synchronize()
        let before = await service.uploadIDs; XCTAssertEqual(before.count, 1)
        let saved = try unwrap(try await reopened.note(localID: local.localID))
        XCTAssertEqual(saved.attachments.first?.nextUploadAttemptAt, clock.read().addingTimeInterval(120))
        await service.failUploads(nil, startingAt: 0); clock.advance(120); await next.synchronize()
        let complete = try unwrap(try await reopened.note(localID: local.localID)); XCTAssertTrue(complete.isSynchronized)
        await next.suspend(); try await reopened.close()
    }

    func testRevokedMediaRecoveryStopsWithoutChangingFrozenRequest() async throws {
        let store = try await open(); let service = NoteSyncTestTransport(scope: scope)
        let local = try await makeImageNote(store)
        await service.failNextSend(.mediaExpired); await service.failUploads(.permissionDenied, startingAt: 2)
        let coordinator = try NoteSyncCoordinator(store: store, service: service)
        await coordinator.resume(); await coordinator.synchronize()
        let blocked = try unwrap(try await store.note(localID: local.localID)); XCTAssertEqual(blocked.syncIssue, "permission_denied")
        XCTAssertNotNil(blocked.pendingOperation)
        await coordinator.synchronize(forceRetry: true)
        let requests = await service.operations; XCTAssertEqual(requests.count, 1)
        let retained = try unwrap(try await store.note(localID: local.localID)); XCTAssertEqual(retained.pendingOperation?.requestBody, blocked.pendingOperation?.requestBody)
        await coordinator.suspend(); try await store.close()
    }
}

actor NoteSyncTestTransport: NoteSyncServing {
    nonisolated let scope: NoteStoreScope
    private(set) var operations: [NotePendingOperation] = []
    private(set) var commitCount = 0
    private(set) var detailIDs: [String] = []
    var remotes: [String: NoteRemoteSnapshot] = [:]
    private var receipts: [String: NoteSyncReceipt] = [:]
    private var manifestOverride: NoteSyncManifest?
    private var manifestFailure: NoteSyncFailure?
    private(set) var manifestCalls = 0
    private(set) var pageCalls = 0
    private var pageHandler: (@Sendable ([String]?) async throws -> [NoteRemoteSnapshot]?)?
    private var failures: [String: NoteSyncFailure] = [:]
    private var loseACK = false
    private var loseUploadACK = false
    private var nextSendFailure: NoteSyncFailure?
    private var uploadReceipts: [String: NoteSyncUploadReceipt] = [:]
    private(set) var uploadIDs: [String] = []
    private var uploadFailure: NoteSyncFailure?
    private var uploadFailureStart = 0
    private var sendHook: (@Sendable (NotePendingOperation) async throws -> Void)?
    private var detailHook: (@Sendable (String) async throws -> Void)?
    private var uploadHook: (@Sendable (NoteLocalAttachment) async throws -> Void)?
    init(scope: NoteStoreScope) { self.scope = scope }
    func overrideManifest(_ value: NoteSyncManifest) { manifestOverride = value }
    func failManifest(_ failure: NoteSyncFailure?) { manifestFailure = failure }
    func setPageHandler(_ handler: @escaping @Sendable ([String]?) async throws -> [NoteRemoteSnapshot]?) { pageHandler = handler }
    func setRemote(_ value: NoteRemoteSnapshot) { remotes[value.assetID] = value }
    func setSendHook(_ hook: (@Sendable (NotePendingOperation) async throws -> Void)?) { sendHook = hook }
    func setDetailHook(_ hook: (@Sendable (String) async throws -> Void)?) { detailHook = hook }
    func setUploadHook(_ hook: (@Sendable (NoteLocalAttachment) async throws -> Void)?) { uploadHook = hook }
    func loseNextAcknowledgment() { loseACK = true }
    func loseNextUploadAcknowledgment() { loseUploadACK = true }
    func failNextSend(_ failure: NoteSyncFailure) { nextSendFailure = failure }
    func failUploads(_ failure: NoteSyncFailure?, startingAt: Int) { uploadFailure = failure; uploadFailureStart = startingAt }
    func failContent(_ value: String, with error: NoteSyncFailure) { failures[value] = error }
    func manifest() async throws -> NoteSyncManifest {
        manifestCalls += 1
        if let manifestFailure { throw manifestFailure }
        return manifestOverride ?? NoteSyncManifest(protocolVersion: 1, complete: true, notes: remotes.values.map { NoteSyncManifest.Entry(assetID: $0.assetID, syncToken: $0.syncToken, lifecycle: $0.lifecycle) })
    }
    func readPage(assetIDs: [String]?) async throws -> [NoteRemoteSnapshot]? {
        pageCalls += 1
        return try await pageHandler?(assetIDs)
    }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        detailIDs.append(assetID); try await detailHook?(assetID)
        guard let value = remotes[assetID] else { throw NoteSyncFailure.notFound }; return value
    }
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt {
        operations.append(operation); try await sendHook?(operation)
        if let existing = receipts[operation.operationID] { return existing }
        if let failure = nextSendFailure { nextSendFailure = nil; throw failure }
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: operation.requestBody) as? [String: Any])
        let content = payload["content"] as? String ?? ""
        if let failure = failures[content] { throw failure }
        commitCount += 1
        let assetID = operation.serverAssetID ?? "asset-\(operation.operationID)"
        let receipt = NoteSyncReceipt(operationID: operation.operationID, assetID: assetID, syncToken: "token-\(commitCount)", noteDocumentVersionID: "nv-\(commitCount)", lifecycle: operation.lifecycle)
        receipts[operation.operationID] = receipt
        let old = remotes[assetID]
        let body = operation.bodyRevision == nil ? old!.body : OfflineNoteBody(content: content, contentJSON: payload["content_json"] as? String, tags: payload["tags"] as? [String] ?? [])
        remotes[assetID] = NoteRemoteSnapshot(assetID: assetID, syncToken: receipt.syncToken, body: body, lifecycle: receipt.lifecycle, isPublic: old?.isPublic ?? false)
        if loseACK { loseACK = false; throw NoteSyncFailure.transient(retryAfter: nil) }
        return receipt
    }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt {
        uploadIDs.append(attachment.uploadID)
        try await uploadHook?(attachment)
        if let uploadFailure, uploadIDs.count >= uploadFailureStart { throw uploadFailure }
        let receipt = uploadReceipts[attachment.uploadID] ?? NoteSyncUploadReceipt(mediaRef: "med_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased(), sha256: attachment.sha256, mimeType: attachment.mimeType, byteCount: data.count)
        uploadReceipts[attachment.uploadID] = receipt
        if loseUploadACK { loseUploadACK = false; throw NoteSyncFailure.transient(retryAfter: nil) }
        return receipt
    }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.permissionDenied }
    nonisolated static func snapshot(_ id: String, token: String, text: String, isPublic: Bool = false) -> NoteRemoteSnapshot {
        NoteRemoteSnapshot(assetID: id, syncToken: token, body: OfflineNoteBody(content: text), lifecycle: .active, isPublic: isPublic)
    }
}

private final class NoteSyncTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1000)
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(interval) }
}

actor NoteSyncTestGate {
    private var isStarted = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func wait() async {
        isStarted = true; startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { waiter = $0 }
    }
    func started() async { if !isStarted { await withCheckedContinuation { startWaiter = $0 } } }
    func release() { waiter?.resume(); waiter = nil }
}
