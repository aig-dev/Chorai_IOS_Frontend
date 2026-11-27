import XCTest
import Combine
import Alamofire
import CoreFlow
import os
@testable import ArcNote

@MainActor
final class NetworkResponseExecutionTests: XCTestCase {
    func testCommittedSparkReplyUnavailableRetriesExactActivity() async throws {
        try await assertCommittedSparkRetry(status: 409, reason: "spark_committed_reply_unavailable", code: "CONFLICT")
    }

    func testCommittedSparkSettlementPendingRetriesExactActivity() async throws {
        try await assertCommittedSparkRetry(status: 503, reason: "spark_committed_settlement_pending", code: "SERVICE_UNAVAILABLE")
    }

    private func assertCommittedSparkRetry(status: Int, reason: String, code: String) async throws {
        let starts = (0..<3).map { expectation(description: "Spark outcome request \($0)") }
        let next = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let index = next.withLock { value in defer { value += 1 }; return value }
            if index < starts.count { starts[index].fulfill() }
        })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-spark-token")
        let suite = "spark-outcome-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SparkSessionStore(actorID: "synthetic-actor", rootSourceAssetID: "card",
            service: NetworkCoreSparkService(network: network),
            persistence: UserDefaultsSparkSessionStore(defaults: defaults))
        let failed = expectation(description: "Committed response unavailable")
        let phase = store.$phase.filter { if case .failed = $0 { return true }; return false }
            .prefix(1).sink { _ in failed.fulfill() }
        defer { phase.cancel() }
        store.start()
        await fulfillment(of: [starts[0]], timeout: 4)
        guard fixture.count == 1 else { return XCTFail("Missing source read") }
        fixture.respond(HTTPFixture.detail)
        await fulfillment(of: [starts[1]], timeout: 4)
        guard fixture.count == 2 else { return XCTFail("Missing Spark execution") }
        XCTAssertEqual(fixture.request(at: 1).httpMethod, "POST")
        let body: [String: Any] = ["success": false, "error": ["code": code, "message": reason,
            "context": ["reason": reason, "activity_id": "act_original"]]]
        fixture.respond(String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self), status: status, at: 1)
        await fulfillment(of: [failed], timeout: 4)
        store.retryTrigger()
        await fulfillment(of: [starts[2]], timeout: 4)
        guard fixture.count == 3 else { return XCTFail("Missing outcome recovery") }
        XCTAssertEqual(fixture.request(at: 2).httpMethod, "GET")
        XCTAssertEqual(fixture.request(at: 2).url?.path, "/api/v1/spark/activities/act_original/results")
        XCTAssertEqual((0..<fixture.count).filter { fixture.request(at: $0).httpMethod == "POST" }.count, 1)
        fixture.respond(#"{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Still unavailable"}}"#, status: 503, at: 2)
    }

    func testUnknownSparkOutcomesPreserveChildWireIdentityAcrossRestart() async throws {
        for outcome in ["lost", "malformed", "spark_commit_unknown", "spark_reservation_unknown", "spark_refund_pending"] {
            let starts = (0..<2).map { expectation(description: "unknown Spark \(outcome) request \($0)") }
            let next = OSAllocatedUnfairLock(initialState: 0)
            let fixture = HTTPFixture(onStart: {
                let index = next.withLock { value in defer { value += 1 }; return value }
                if index < starts.count { starts[index].fulfill() }
            })
            let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
            network.setAuthToken("synthetic-spark-token")
            let suite = "spark-unknown-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = UserDefaultsSparkSessionStore(defaults: defaults)
            let key = UUID()
            try persistence.save(.init(actorID: "synthetic-actor", rootSourceAssetID: "root",
                nodes: [.init(sourceAssetID: "root", sourcePreview: "Root", activityID: "act_parent", parentActivityID: nil,
                    rootActivityID: "act_parent", chainDepth: 0, visibleIndex: 0)], activeActivityID: "act_parent",
                pendingTrigger: .init(requestKey: key, sourceAssetID: "card", sourcePreview: "Child", parentActivityID: "act_parent",
                    startedAt: Date(), priorActivityID: "act_parent", priorVisibleIndex: 0), didShowUpwardCue: false))
            let first = SparkSessionStore(actorID: "synthetic-actor", rootSourceAssetID: "root",
                service: NetworkCoreSparkService(network: network), persistence: persistence)
            let failed = expectation(description: "unknown result retained")
            let observer = first.$phase.filter { if case .failed = $0 { return true }; return false }.prefix(1).sink { _ in failed.fulfill() }
            defer { observer.cancel() }
            first.start()
            await fulfillment(of: [starts[0]], timeout: 4)
            guard fixture.count == 1 else { return XCTFail("Expected original POST") }
            if outcome == "lost" { fixture.fail() }
            else if outcome == "malformed" { fixture.respond("{", status: 201) }
            else {
                let body: [String: Any] = ["success": false, "error": ["code": "SERVICE_UNAVAILABLE", "message": outcome,
                    "context": ["reason": outcome, "activity_id": "act_original"]]]
                fixture.respond(String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self), status: 503)
            }
            await fulfillment(of: [failed], timeout: 4)
            let retained = try XCTUnwrap(persistence.snapshot(actorID: "synthetic-actor", rootSourceAssetID: "root")?.pendingTrigger)
            XCTAssertEqual(retained.requestKey, key)
            XCTAssertNil(retained.committedActivityID)
            let restarted = SparkSessionStore(actorID: "synthetic-actor", rootSourceAssetID: "root",
                service: NetworkCoreSparkService(network: network), persistence: persistence)
            restarted.start()
            await fulfillment(of: [starts[1]], timeout: 4)
            guard fixture.count == 2 else { return XCTFail("Expected original operation retry") }
            let original = fixture.request(), retry = fixture.request(at: 1)
            XCTAssertEqual(original.httpMethod, "POST"); XCTAssertEqual(retry.httpMethod, "POST")
            XCTAssertEqual(retry.url, original.url)
            XCTAssertEqual(original.value(forHTTPHeaderField: "Idempotency-Key"), key.uuidString.lowercased())
            XCTAssertEqual(retry.value(forHTTPHeaderField: "Idempotency-Key"), original.value(forHTTPHeaderField: "Idempotency-Key"))
            let originalBytes = try sparkRequestBody(original)
            XCTAssertEqual(try sparkRequestBody(retry), originalBytes)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes) as? [String: String])
            XCTAssertEqual(body, ["parent_activity_id": "act_parent"])
            fixture.respond(#"{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Unavailable"}}"#, status: 503, at: 1)
        }
    }

    private func sparkRequestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    func testRetiredSparkServiceRejectsLateReceiptAndCannotPostAsReplacementAccount() async throws {
        let started = expectation(description: "original Spark POST")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-first-token")
        let service = NetworkCoreSparkService(network: network)
        let rejected = expectation(description: "retired late receipt rejected")
        let request = service.trigger(sourceAssetID: "card", parentActivityID: nil, requestKey: UUID())
            .sink(receiveCompletion: { completion in
                guard case .failure(.unauthorized) = completion else { XCTFail("Expected retired session rejection"); rejected.fulfill(); return }
                rejected.fulfill()
            }, receiveValue: { _ in XCTFail("Retired Spark receipt was adopted") })
        defer { request.cancel() }
        await fulfillment(of: [started], timeout: 4)
        network.setAuthToken("synthetic-replacement-token")
        fixture.respond(#"{"success":true,"data":{"activity_id":"act_original","root_activity_id":"act_original","chain_depth":0,"groups":{"related":{"name":"related","items":[]},"angles":{"name":"angles","items":[]},"keywords":{"name":"keywords","items":[]}}}}"#, status: 201)
        await fulfillment(of: [rejected], timeout: 4)
        let retryRejected = expectation(description: "old service dispatch rejected")
        let retry = service.trigger(sourceAssetID: "card", parentActivityID: nil, requestKey: UUID())
            .sink(receiveCompletion: { completion in
                guard case .failure(.unauthorized) = completion else { XCTFail("Old service must not dispatch"); retryRejected.fulfill(); return }
                retryRejected.fulfill()
            }, receiveValue: { _ in XCTFail("Unexpected value") })
        defer { retry.cancel() }
        await fulfillment(of: [retryRejected], timeout: 4)
        XCTAssertEqual(fixture.count, 1)
    }

    func testAcknowledgedSparkHydrationFailureRetriesOriginalActivityWithoutPosting() async throws {
        try await assertAcknowledgedSparkHydrationFailure(status: 503)
    }

    func testAcknowledgedSparkHydrationUnauthorizedRetainsOriginalActivity() async throws {
        try await assertAcknowledgedSparkHydrationFailure(status: 401)
    }

    private func assertAcknowledgedSparkHydrationFailure(status: Int) async throws {
        let starts = (0..<4).map { expectation(description: "Spark request \($0)") }
        let next = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let index = next.withLock { value in defer { value += 1 }; return value }
            if index < starts.count { starts[index].fulfill() }
        })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-spark-token")
        let suite = "spark-recovery-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SparkSessionStore(
            actorID: "synthetic-actor", rootSourceAssetID: "card",
            service: NetworkCoreSparkService(network: network),
            persistence: UserDefaultsSparkSessionStore(defaults: defaults)
        )
        let failed = expectation(description: "Acknowledged result read failed")
        let phase = store.$phase.filter { if case .failed = $0 { return true }; return false }
            .prefix(1).sink { _ in failed.fulfill() }
        defer { phase.cancel() }

        store.start()
        await fulfillment(of: [starts[0]], timeout: 4)
        guard fixture.count == 1 else { return XCTFail("Missing source read") }
        XCTAssertEqual(fixture.request().url?.path, "/api/cards/card")
        fixture.respond(HTTPFixture.detail)
        await fulfillment(of: [starts[1]], timeout: 4)
        guard fixture.count == 2 else { return XCTFail("Missing Spark execution") }
        XCTAssertEqual(fixture.request(at: 1).url?.path, "/api/v1/assets/card/spark")
        XCTAssertEqual(fixture.request(at: 1).httpMethod, "POST")
        fixture.respond(#"{"success":true,"data":{"activity_id":"act_original","root_activity_id":"act_original","chain_depth":0,"groups":{"related":{"name":"related","items":[{"asset_id":"result","version_id":"ver_result","score":1,"origin":"semantic","bucket":"related"}]},"angles":{"name":"angles","items":[]},"keywords":{"name":"keywords","items":[]}}}}"#, status: 201, at: 1)
        await fulfillment(of: [starts[2]], timeout: 4)
        guard fixture.count == 3 else { return XCTFail("Missing result hydration") }
        XCTAssertEqual(fixture.request(at: 2).url?.path, "/api/cards/result")
        fixture.respond(#"{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Result read unavailable"}}"#, status: status, at: 2)
        await fulfillment(of: [failed], timeout: 4)

        store.retryTrigger()
        await fulfillment(of: [starts[3]], timeout: 4)
        guard fixture.count == 4 else { return XCTFail("Missing recovery read") }
        XCTAssertEqual(fixture.request(at: 3).httpMethod, "GET")
        XCTAssertEqual(fixture.request(at: 3).url?.path, "/api/v1/spark/activities/act_original/results")
        XCTAssertEqual((0..<fixture.count).filter { fixture.request(at: $0).httpMethod == "POST" }.count, 1)
        fixture.respond(#"{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Still unavailable"}}"#, status: 503, at: 3)
    }

    func testScopedBackgroundUploadPatchAndDeleteUseOriginalWireIdentity() async throws {
        let admission = NoteBackgroundGeneration().admission(for: 0)
        prepareLinkAuth()
        let starts = (0..<4).map { expectation(description: "background request \($0)") }
        let next = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let index = next.withLock { value in defer { value += 1 }; return value }
            if index < starts.count { starts[index].fulfill() }
        })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-link-token")
        let scope = NoteStoreScope(actorID: "link_actor", environmentID: fixture.baseURL)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        addTeardownBlock { try await store.close(); try FileManager.default.removeItem(at: root) }
        let snapshot = NoteRemoteSnapshot(assetID: "asset", syncToken: "token", body: .init(content: "fixture"), lifecycle: .active, isPublic: false)
        let imported = try await store.applyRemote(snapshot, localID: nil, expectedGeneration: nil)
        let localID = try XCTUnwrap(imported?.localID)
        let bytes = try XCTUnwrap(Data(base64Encoded: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABgAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z"))
        let image = CardEditingImage(data: bytes, filename: "fixture.png", mimeType: "image/jpeg")
        let staged = try await store.stageBackground(localID: localID, assetID: "asset", baseline: 7, image: image, expected: nil, createPlaceholder: false, admission: admission)
        let command = try await store.advanceBackground(staged, assetID: "asset", phase: .submitted, admission: admission)
        let file = try XCTUnwrap(command.image)
        let ref = "med_1234567890abcdef"
        let content = APIEnvironment.mediaContentPath(ref)
        let display = content + "?asset_id=asset"
        func card(_ revision: Int, ref: String? = nil) -> String {
            var data: [String: Any] = ["id":"asset","owner_actor_id":"link_actor","background_revision":revision]
            if let ref { data["background_media_ref"] = ref }
            return String(decoding: try! JSONSerialization.data(withJSONObject: ["success":true,"data":data]), as: UTF8.self)
        }

        let read = Task { try await network.backgroundObservation(scope: scope, asset: "asset") }
        await fulfillment(of: [starts[0]], timeout: 4)
        guard fixture.count == 1 else { read.cancel(); return XCTFail("Missing owner read") }
        XCTAssertEqual(fixture.request().httpMethod, "GET")
        XCTAssertEqual(fixture.request().url?.path, "/api/cards/asset")
        fixture.respond(card(7))
        let prior = try await read.value
        XCTAssertEqual(prior.revision, 7)
        let upload = Task { try await network.uploadBackground(command, bytes: bytes) }
        await fulfillment(of: [starts[1]], timeout: 4)
        guard fixture.count == 2 else { upload.cancel(); return XCTFail("Missing upload") }
        let request = fixture.request(at: 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/media/upload")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), command.id.uuidString)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
        let descriptor: [String: Any] = ["bucket":"private","object_key":"test","media_ref":ref,"public_url":content,"mime":file.mimeType,
            "size_bytes":bytes.count,"width":3,"height":2,"sha256":file.sha256,"upload_kind":"background"]
        fixture.respond(String(decoding: try JSONSerialization.data(withJSONObject: ["success":true,"data":descriptor]), as: UTF8.self), status: 201, at: 1)
        let verified = try await upload.value
        let linked = try await store.advanceBackground(command, assetID: "asset", phase: .attachedRef, ref: verified, admission: admission)
        let patch = Task { try await network.writeBackground(linked) }
        await fulfillment(of: [starts[2]], timeout: 4)
        guard fixture.count == 3 else { patch.cancel(); return XCTFail("Missing attachment") }
        let patchRequest = fixture.request(at: 2)
        XCTAssertEqual(patchRequest.url?.path, "/api/cards/asset/background")
        XCTAssertEqual(patchRequest.httpMethod, "PATCH")
        XCTAssertEqual(patchRequest.value(forHTTPHeaderField: "If-Match"), "\"7\"")
        let data: Data
        if let body = patchRequest.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(patchRequest.httpBodyStream)
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = stream.read(&buffer, maxLength: buffer.count)
            data = Data(buffer.prefix(max(0,count)))
        }
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data), ["background_media_ref":ref])
        fixture.respond(card(8, ref: display), at: 2)
        let current = try await patch.value
        XCTAssertEqual(current.displayRef, display)
        try await store.retireBackground(linked, current: current, admission: admission)
        let removal = try await store.stageBackground(localID: localID, assetID: "asset", baseline: 8, image: nil, expected: nil, createPlaceholder: false, admission: admission)
        let frozen = try await store.advanceBackground(removal, assetID: "asset", phase: .submitted, admission: admission)
        let clear = Task { try await network.writeBackground(frozen) }
        await fulfillment(of: [starts[3]], timeout: 4)
        guard fixture.count == 4 else { clear.cancel(); return XCTFail("Missing removal") }
        XCTAssertEqual(fixture.request(at: 3).httpMethod, "DELETE")
        XCTAssertEqual(fixture.request(at: 3).value(forHTTPHeaderField: "If-Match"), "\"8\"")
        fixture.respond(card(9), at: 3)
        let absent = try await clear.value
        XCTAssertNil(absent.displayRef)
        XCTAssertEqual(absent.revision, 9)
    }

    private func pinFixture() async throws -> (LocalNotesController, NoteStoreScope, ToggleCardPinResponse) {
        prepareLinkAuth()
        let scope = try XCTUnwrap(AuthManager.shared.currentNoteScope)
        let library = NoteLibraryStore(rootURL: linkJournalDirectory(), service: { HomeOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: true)
        let owner = LocalNotesController(library: library, access: { (scope, true) })
        let json = #"{"id":"remote","content":"","is_public":false,"tags":[],"created_at":"now","updated_at":"now","favorite_count":0,"like_count":0,"view_count":0,"comment_count":0,"rate":0,"is_pinned":true,"pinned_at":"now"}"#
        let card = try JSONDecoder().decode(Card.self, from: Data(json.utf8))
        return (owner, scope, .init(success: true, message: nil, data: card, errorCode: nil))
    }

    func testPinAcceptsRemoteOnlyCanonicalCardAndDeniesUnsyncedLocalRows() async throws {
        let (owner, scope, response) = try await pinFixture()
        let draft = try await owner.library.save(identifier: nil, createID: "unsent", body: .init(content: "Fixture"), scope: scope)
        for id in [NoteLibraryStore.identifier(draft), "local-note:unbound"] {
            do {
                _ = try await owner.setPinned(identifier: id, isPinned: true) { _, complete in
                    XCTFail("Dispatched an unbound local row")
                    complete(.success(response))
                }
                XCTFail("Accepted an unbound local row")
            } catch NoteLocalStoreError.invalidScope {}
        }
        let commit = try await owner.setPinned(identifier: "remote", isPinned: true) { asset, complete in
            XCTAssertEqual(asset, "remote")
            complete(.success(response))
        }
        XCTAssertEqual(commit, .pin(cardID: "remote", isPinned: true, pinnedAt: "now"))
        XCTAssertFalse(owner.library.notes.contains { $0.serverAssetID == "remote" })
    }

    func testPinRejectsCanonicalReplyAfterSameActorSessionOrLibraryScopeChanges() async throws {
        let (owner, scope, response) = try await pinFixture()
        do {
            _ = try await owner.setPinned(identifier: "remote", isPinned: true) { _, complete in
                self.prepareLinkAuth()
                complete(.success(response))
            }
            XCTFail("Accepted the previous login’s response")
        } catch NoteLocalStoreError.invalidScope {}
        let other = NoteStoreScope(actorID: "another-fixture", environmentID: scope.environmentID)
        do {
            _ = try await owner.setPinned(identifier: "remote", isPinned: true) { _, complete in
                Task { @MainActor in
                    await owner.library.configure(scope: other, cloudEnabled: false)
                    complete(.success(response))
                }
            }
            XCTFail("Accepted the previous library’s response")
        } catch NoteLocalStoreError.invalidScope {}
        XCTAssertEqual(owner.library.scope, other)
        XCTAssertTrue(owner.library.notes.isEmpty)
    }

    func testCanceledPolicyResponseCannotSettleTheRecoveredRequest() async throws {
        prepareLinkAuth()
        let started = expectation(description: "privacy command dispatched")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let scope = NoteStoreScope(actorID: "link_actor", environmentID: fixture.baseURL)
        let token = "vp1." + String(repeating: "A", count: 43)
        let bytes = try JSONSerialization.data(withJSONObject: ["success": true, "data": ["current_policy":
            ["asset_id": "source", "space_id": NSNull(), "visibility": "PRIVATE", "policy_token": token]]])
        let policy = try NotePrivacyWire.decode(status: 200, data: bytes, assetID: "source")
        let directory = linkJournalDirectory()
        let journal = NotePrivacyJournal(directory: directory)
        let attempt = try await journal.begin(scope: scope, path: APIEnvironment.visibilityPath(assetID: "source"), observed: policy, desired: .PUBLIC)
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-link-token")
        let operation = Task { try await network.notePrivacyRequest(scope: scope, assetID: "source", command: attempt) }
        await fulfillment(of: [started], timeout: 5)
        let request = try XCTUnwrap(fixture.count == 1 ? fixture.request() : nil)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/assets/source/visibility")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), attempt.requestID.uuidString)
        operation.cancel()
        fixture.respond("{}")
        do { _ = try await operation.value; XCTFail("Canceled request accepted") } catch is CancellationError {}
        let retained = try await NotePrivacyJournal(directory: directory).pending(scope: scope, assetID: "source")
        XCTAssertEqual(retained, attempt)
    }

    func testBodyEditingAdapterExcludesPrivacyFromTransport() async throws {
        let started = expectation(description: "body update")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let service = NetworkCoreCardEditingService(network: NetworkManager(baseURL: fixture.baseURL, session: fixture.session))
        let operation = Task { try await service.update(cardID: "source",
            draft: CardEditingDraft(title: "title", content: "body", tags: [], isPublic: true)) }
        await fulfillment(of: [started], timeout: 5)
        let request = try XCTUnwrap(fixture.count == 1 ? fixture.request() : nil)
        let bytes: Data
        if let body = request.httpBody { bytes = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let length = stream.read(&buffer, maxLength: buffer.count)
            XCTAssertGreaterThan(length, 0)
            bytes = Data(buffer.prefix(max(0, length)))
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(body["is_public"])
        XCTAssertEqual(body["content"] as? String, "body")
        fixture.respond(HTTPFixture.detail)
        _ = try? await operation.value
    }

    private func purgeReceipt(_ key: String, cleanup: String = "PENDING") -> String {
        #"{"success":true,"data":{"asset_id":"source","request_id":"\#(key)","state":"ERASED","activity_id":"purge_activity","action_log_id":"purge_log","certificate_id":"certificate","cleanup_state":"\#(cleanup)"}}"#
    }

    func testPurgeLostAckAndWrongReceiptRetryTheFrozenBytesAndExactIdentity() async throws {
        prepareLinkAuth()
        let starts = (0..<3).map { expectation(description: "purge request \($0)") }
        let next = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let index = next.withLock { value in defer { value += 1 }; return value }
            if index < starts.count { starts[index].fulfill() }
        })
        let attempt = try NotePurgeWriteAttempt(scope: NoteStoreScope(actorID: "link_actor", environmentID: fixture.baseURL),
            assetID: "source", localID: "local_note", localGeneration: 2, baseSyncToken: "displayed_trash")
        for index in 0..<3 {
            let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
            network.setAuthToken("synthetic-link-token")
            let operation = Task { try await network.permanentlyDeleteNote(attempt) }
            await fulfillment(of: [starts[index]], timeout: 5)
            guard fixture.count > index else { operation.cancel(); _ = try await operation.value; throw URLError(.timedOut) }
            let request = fixture.request(at: index)
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/cards/trash/source/permanent")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), attempt.requestID)
            // URLProtocol exposes upload bytes as a stream on some runtimes;
            // the frozen body itself is covered through SQLite reopen tests.
            if let bytes = request.httpBody { XCTAssertEqual(bytes, attempt.requestBody) }
            if index == 0 { fixture.fail(at: index) }
            else { fixture.respond(purgeReceipt(index == 1 ? "wrong_key" : attempt.requestID), at: index) }
            if index < 2 {
                do { _ = try await operation.value; XCTFail("Unverified erase acknowledged") } catch {}
            } else {
                let receipt = try await operation.value
                XCTAssertEqual(receipt.requestID, attempt.requestID)
                XCTAssertEqual(receipt.cleanupState, .pending)
            }
        }
    }

    func testPurgeSameActorNewSessionRejectsLateResponse() async throws {
        prepareLinkAuth()
        let started = expectation(description: "purge request")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let attempt = try NotePurgeWriteAttempt(scope: NoteStoreScope(actorID: "link_actor", environmentID: fixture.baseURL),
            assetID: "source", localID: "local_note", localGeneration: 2, baseSyncToken: "displayed_trash")
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-link-token")
        let operation = Task { try await network.permanentlyDeleteNote(attempt) }
        await fulfillment(of: [started], timeout: 5)
        guard fixture.count > 0 else { operation.cancel(); _ = try await operation.value; throw URLError(.timedOut) }
        prepareLinkAuth()
        fixture.respond(purgeReceipt(attempt.requestID))
        do { _ = try await operation.value; XCTFail("Previous login response accepted") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testPurgeUnknownCleanupReceiptIsRejected() async throws {
        prepareLinkAuth()
        let started = expectation(description: "purge request")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let attempt = try NotePurgeWriteAttempt(scope: NoteStoreScope(actorID: "link_actor", environmentID: fixture.baseURL),
            assetID: "source", localID: "local_note", localGeneration: 2, baseSyncToken: "displayed_trash")
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        network.setAuthToken("synthetic-link-token")
        let operation = Task { try await network.permanentlyDeleteNote(attempt) }
        await fulfillment(of: [started], timeout: 5)
        guard fixture.count > 0 else { operation.cancel(); _ = try await operation.value; throw URLError(.timedOut) }
        fixture.respond(purgeReceipt(attempt.requestID, cleanup: "UNKNOWN"))
        do { _ = try await operation.value; XCTFail("Unknown cleanup state accepted") } catch {}
    }

    private func linkJournalDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func linkReceipt(_ key: String) -> String {
        #"{"success":true,"data":{"note_link_id":"exact_link","source_asset_id":"source","target_asset_id":"target","created_at":"2026-11-21T00:00:00Z","state":"ACTIVE","client_request_id":"\#(key)","activity_id":"original_activity","action_log_id":"original_log"}}"#
    }

    func testLinkLostAckAndMismatchedSuccessRetainTheExactRequestAcrossReopen() async throws {
        prepareLinkAuth()
        let starts = (0..<3).map { expectation(description: "link request \($0)") }
        let next = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let index = next.withLock { value in defer { value += 1 }; return value }
            if index < starts.count { starts[index].fulfill() }
        })
        let root = linkJournalDirectory()
        var originalKey: String?
        for index in 0..<3 {
            let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session,
                linkWriteJournal: NoteLinkWriteJournal(directory: root))
            network.setAuthToken("synthetic-link-token")
            let operation = Task { try await network.createCardLink(cardId: "source", reques: LinkRequest(linkedCardId: "target")) }
            await fulfillment(of: [starts[index]], timeout: 5)
            guard fixture.count > index else {
                operation.cancel()
                _ = try await operation.value
                throw URLError(.timedOut)
            }
            let key = try XCTUnwrap(fixture.request(at: index).value(forHTTPHeaderField: "Idempotency-Key"))
            if let originalKey { XCTAssertEqual(key, originalKey) } else { originalKey = key }
            if index == 0 { fixture.fail(at: index) }
            else { fixture.respond(linkReceipt(index == 1 ? "wrong_key" : key), status: 201, at: index) }
            if index < 2 {
                do { _ = try await operation.value; XCTFail("An unconfirmed receipt must retain the request") } catch {}
            } else {
                let value = try await operation.value
                XCTAssertEqual(value.data.linkId, "exact_link")
            }
        }
        let nextAttempt = try await NoteLinkWriteJournal(directory: root).begin(apiBaseURL: fixture.baseURL, actorID: "link_actor", operation: .link, sourceID: "source", targetID: "target")
        XCTAssertNotEqual(nextAttempt.requestID, originalKey)
    }

    func testLinkAccountChangeRejectsLateReceiptWithoutClearingOriginalPendingRequest() async throws {
        prepareLinkAuth()
        let started = expectation(description: "link request")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let root = linkJournalDirectory()
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session,
            linkWriteJournal: NoteLinkWriteJournal(directory: root))
        network.setAuthToken("synthetic-link-token")
        let operation = Task { try await network.createCardLink(cardId: "source", reques: LinkRequest(linkedCardId: "target")) }
        await fulfillment(of: [started], timeout: 5)
        guard fixture.count > 0 else {
            operation.cancel()
            _ = try await operation.value
            throw URLError(.timedOut)
        }
        let key = try XCTUnwrap(fixture.request().value(forHTTPHeaderField: "Idempotency-Key"))
        AuthManager.shared.installUITestSession(token: "other-token", actorID: "other_actor", email: "other@fixture.invalid", username: "Other", createdAt: "2026-11-21T00:00:00Z")
        fixture.respond(linkReceipt(key), status: 201)
        do { _ = try await operation.value; XCTFail("The previous account cannot deliver into the new session") }
        catch is CancellationError {} catch { XCTFail("Expected session cancellation, got \(error)") }
        let retained = try await NoteLinkWriteJournal(directory: root).begin(apiBaseURL: fixture.baseURL, actorID: "link_actor", operation: .link, sourceID: "source", targetID: "target")
        XCTAssertEqual(retained.requestID, key)
    }

    func testUnlinkLostAckResolvesOriginalIdentityBeforeTheReplacement() async throws {
        prepareLinkAuth()
        let starts = (0..<3).map { expectation(description: "unlink request \($0)") }
        let next = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let index = next.withLock { value in defer { value += 1 }; return value }
            if index < starts.count { starts[index].fulfill() }
        })
        let root = linkJournalDirectory()
        var originalKey: String?
        for index in 0..<3 {
            let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session,
                linkWriteJournal: NoteLinkWriteJournal(directory: root))
            network.setAuthToken("synthetic-link-token")
            let operation = Task { try await network.deleteCardLink(cardId: "source", linkedCardId: "target",
                noteLinkID: index == 0 ? "old_link" : "replacement") }
            await fulfillment(of: [starts[index]], timeout: 5)
            guard fixture.count > index else {
                operation.cancel()
                _ = try await operation.value
                throw URLError(.timedOut)
            }
            let request = fixture.request(at: index)
            let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
            let exact = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "note_link_id" })?.value)
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(exact, index < 2 ? "old_link" : "replacement")
            if index == 0 { originalKey = key; fixture.fail(at: index) }
            else {
                fixture.respond(#"{"success":true,"data":{"note_link_id":"\#(exact)","source_asset_id":"source","target_asset_id":"target","removed":true,"client_request_id":"\#(key)","activity_id":"original_activity","action_log_id":"original_log"}}"#, at: index)
            }
            if index < 2 {
                XCTAssertEqual(key, originalKey)
                do { _ = try await operation.value; XCTFail("A recovered old unlink cannot acknowledge the replacement") }
                catch let error as NetworkError where index == 1 {
                    guard case .api(_, let code, _, _) = error else { return XCTFail("Expected recovery result") }
                    XCTAssertEqual(code, "link_previous_request_recovered")
                } catch { if index == 1 { XCTFail("Unexpected recovery result: \(error)") } }
            } else {
                XCTAssertNotEqual(key, originalKey)
                let response = try await operation.value
                XCTAssertEqual(response.data?.noteLinkID, "replacement")
            }
        }
    }

    func testCurrentImportContractDecodesWithoutRetiredSoulFields() throws {
        // Current Go DTO: recovery identity, file lifecycle, and RFC3339 dates.
        let summary = #"{"job_id":"job_live","client_request_id":"req_live","status":"running","total_files":2,"imported_count":0,"updated_count":0,"skipped_count":0,"failed_count":0,"created_at":"2026-11-20T16:35:00.123456Z"}"#
        let decoded = try JSONDecoder().decode(
            NoteImportJobListResponse.self,
            from: Data("{\"jobs\":[\(summary)]}".utf8)
        )
        let jobs = try NetworkNoteImportService.mapJobs(decoded)
        XCTAssertEqual(jobs.first?.clientRequestID, "req_live")
        XCTAssertEqual(jobs.first?.status.rawValue, "running")
        XCTAssertEqual(jobs.first?.isSettled, false)

        let detail = #"{"job_id":"job_live","client_request_id":"req_live","status":"done","total_files":2,"imported_count":1,"updated_count":0,"skipped_count":0,"failed_count":1,"created_at":"2026-11-20T16:35:00.123456Z","completed_at":"2026-11-20T16:36:00Z","items":[{"source_key":"good","original_filename":"note.md","original_format":"markdown","asset_id":"asset_live","asset_version_id":"version_live","status":"imported"},{"source_key":"empty","original_filename":"empty.md","original_format":"markdown","status":"failed","error_message":"Import could not be completed."}]}"#
        let value = try NetworkNoteImportService.mapJob(
            JSONDecoder().decode(NoteImportJobDetailResponse.self, from: Data(detail.utf8))
        )
        XCTAssertTrue(value.isSettled)
        XCTAssertEqual(value.clientRequestID, "req_live")
        XCTAssertEqual(value.importedCount, 1)
        XCTAssertEqual(value.failedCount, 1)
        XCTAssertEqual(value.items.first?.assetVersionID, "version_live")
        XCTAssertEqual(value.items.last?.status.rawValue, "failed")
    }

    func testChatStreamKeepsFrameOrderAndDeliversOnMain() async {
        let started = expectation(description: "stream started")
        let completed = expectation(description: "stream completed")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        var ids: [String] = []
        let token = network.streamConversationEvents(conversationId: "chat", lastEventID: "9")
            .sink(receiveCompletion: { completion in
                XCTAssertTrue(Thread.isMainThread)
                if case .failure(let error) = completion { XCTFail("\(error)") }
                completed.fulfill()
            }, receiveValue: { event in
                XCTAssertTrue(Thread.isMainThread)
                ids.append(event.id ?? "missing")
            })
        await fulfillment(of: [started], timeout: 3)
        let frames = (10..<510).map { "event: agent.thinking\nid: \($0)\ndata: {\"source_message_id\":\"synthetic\"}\n\n" }.joined()
        fixture.respond(frames, contentType: "text/event-stream")
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(ids, (10..<510).map(String.init))
        withExtendedLifetime(token) {}
    }

    func testCancelChatStreamCancelsTransportAndRejectsLateFrames() async {
        let started = expectation(description: "stream started")
        let canceled = expectation(description: "transport canceled")
        let fixture = HTTPFixture(onStart: { started.fulfill() }, onStop: { canceled.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let token = network.streamConversationEvents(conversationId: "chat", lastEventID: nil)
            .sink(receiveCompletion: { _ in XCTFail("Canceled stream delivered completion") }, receiveValue: { _ in XCTFail("Canceled stream delivered a frame") })
        await fulfillment(of: [started], timeout: 3)
        token.cancel()
        await fulfillment(of: [canceled], timeout: 3)
        fixture.respond("event: agent.thinking\nid: 1\ndata: {}\n\n", contentType: "text/event-stream")
    }

    private struct Probe: Codable {
        let decodedOnMain: Bool
        init(from decoder: Decoder) throws {
            _ = try decoder.container(keyedBy: Keys.self).decode(Bool.self, forKey: .success)
            decodedOnMain = Thread.isMainThread
        }
        enum Keys: String, CodingKey { case success }
    }

    func testDecodeLeavesMainAndDeliveryReturnsToMain() async {
        let started = expectation(description: "started")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let done = expectation(description: "done")
        let token = network.request(endpoint: "/probe", responseType: Probe.self).sink(receiveCompletion: { _ in done.fulfill() }, receiveValue: {
            XCTAssertFalse($0.decodedOnMain)
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(network.isLoading)
        })
        await fulfillment(of: [started], timeout: 3)
        fixture.respond(#"{"success":true}"#)
        await fulfillment(of: [done], timeout: 3)
        withExtendedLifetime(token) {}
    }

    func testErrorMappingsAndMainThreadAlert() async {
        let cases: [(Int, String, Bool, String)] = [
            (200, "not-json", false, "decode"),
            (401, #"{"error_code":"UNAUTHORIZED","message":"Expired"}"#, false, "unauthorized"),
            (409, #"{"success":false,"error_code":"CONFLICT","message":"Conflict"}"#, false, "api:409"),
            (401, #"{"success":false,"error_code":"INVALID_CREDENTIALS","message":"Invalid"}"#, true, "api:401"),
            (200, #"{"success":false,"error_code":"INVALID_CREDENTIALS","message":"Invalid"}"#, true, "api:200")
        ]
        for (status, body, credential, expected) in cases {
            let started = expectation(description: "started")
            let done = expectation(description: "done")
            let fixture = HTTPFixture(onStart: { started.fulfill() })
            var alertCount = 0
            let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session, errorPresenter: { _ in
                XCTAssertTrue(Thread.isMainThread); alertCount += 1
            })
            network.setAuthToken("synthetic")
            let token = network.request(endpoint: "/probe", responseType: Probe.self, isCredentialExchange: credential)
                .sink(receiveCompletion: {
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertFalse(network.isLoading)
                    guard case .failure(let error) = $0 else { XCTFail("Expected failure"); done.fulfill(); return }
                    let actual: String
                    switch error {
                    case .decodingError: actual = "decode"
                    case .unauthorized: actual = "unauthorized"
                    case .api(let code, _, _, _): actual = "api:\(code)"
                    default: actual = "unexpected"
                    }
                    XCTAssertEqual(actual, expected)
                    done.fulfill()
                }, receiveValue: { _ in XCTFail("Unexpected value") })
            await fulfillment(of: [started], timeout: 3)
            fixture.respond(body, status: status)
            await fulfillment(of: [done], timeout: 3)
            XCTAssertEqual(alertCount, status >= 400 ? 1 : 0)
            withExtendedLifetime(token) {}
        }
    }

    func testClearedAuthenticationSuppressesStale401Alert() async {
        let started = expectation(description: "started")
        let done = expectation(description: "done")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session, errorPresenter: { _ in XCTFail("Stale alert") })
        network.setAuthToken("synthetic")
        let token = network.request(endpoint: "/probe", responseType: Probe.self).sink(receiveCompletion: { _ in done.fulfill() }, receiveValue: { _ in XCTFail() })
        await fulfillment(of: [started], timeout: 3)
        network.clearAuthToken()
        fixture.respond(#"{"error_code":"UNAUTHORIZED","message":"Expired"}"#, status: 401)
        await fulfillment(of: [done], timeout: 3)
        withExtendedLifetime(token) {}
    }

    func testMediaUploadDeliversSuccessAndFailureOnMain() async {
        for success in [true, false] {
            let started = expectation(description: "started")
            let done = expectation(description: "done")
            let fixture = HTTPFixture(onStart: { started.fulfill() })
            let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
            let token = network.uploadCardMedia(data: Data([1,2,3]), filename: "fixture.jpg", mimeType: "image/jpeg").sink(receiveCompletion: {
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertFalse(network.isLoading)
                if success {
                    if case .failure = $0 { XCTFail("Unexpected failure") }
                } else {
                    guard case .failure(.serverError(0, _)) = $0 else { XCTFail("Mapping changed"); done.fulfill(); return }
                }
                done.fulfill()
            }, receiveValue: { value in XCTAssertTrue(success); XCTAssertTrue(value.success); XCTAssertTrue(Thread.isMainThread) })
            await fulfillment(of: [started], timeout: 3)
            fixture.respond(success ? #"{"success":true}"# : #"{"success":false,"message":"Cannot upload"}"#)
            await fulfillment(of: [done], timeout: 3)
            withExtendedLifetime(token) {}
        }
    }

    func testMutationRemainsEagerAndTwoSubscribersShareOneWrite() async {
        let started = expectation(description: "started")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let publisher = network.request(endpoint: "/mutation", method: .post, responseType: Probe.self)
        await fulfillment(of: [started], timeout: 3)
        let done = expectation(description: "both"); done.expectedFulfillmentCount = 2
        let one = publisher.sink(receiveCompletion: { _ in done.fulfill() }, receiveValue: { _ in })
        let two = publisher.sink(receiveCompletion: { _ in done.fulfill() }, receiveValue: { _ in })
        fixture.respond(#"{"success":true}"#)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(fixture.count, 1)
        withExtendedLifetime((one, two)) {}
    }

    func testAsyncServiceCanRequestFromWorkerAndResumeMappingOffMain() async throws {
        let started = expectation(description: "started")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let service = NetworkCoreInterestSelectionService(network: network)
        let operation = Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let domains = try await service.fetchOptions()
            XCTAssertFalse(Thread.isMainThread)
            return domains
        }
        await fulfillment(of: [started], timeout: 3)
        fixture.respond(#"{"success":true,"data":{"domains":["science","design"]}}"#)
        let domains = try await operation.value
        XCTAssertEqual(domains, ["science", "design"])
        XCTAssertEqual(fixture.count, 1)
    }

    func testPublisherBridgeKeepsImmediateValueEmptyCompletionAndFailure() async throws {
        let cached = Future<Int, NetworkError> { $0(.success(7)) }
            .handleEvents(receiveSubscription: { _ in XCTAssertTrue(Thread.isMainThread) })
            .eraseToAnyPublisher()
        let value = try await NetworkManager.firstValue(cached)
        XCTAssertEqual(value, 7)
        let empty = try await NetworkManager.firstValue(Empty<Int, NetworkError>().eraseToAnyPublisher())
        XCTAssertNil(empty)
        do {
            _ = try await NetworkManager.firstValue(Fail<Int, NetworkError>(error: .timeout).eraseToAnyPublisher())
            XCTFail("Expected original transport failure")
        } catch NetworkError.timeout {} catch { XCTFail("Unexpected: \(error)") }
    }

    func testPublisherBridgeCancellationReleasesSubscriptionOnMain() async throws {
        let started = expectation(description: "subscribed")
        let cancelled = expectation(description: "cancelled")
        let subject = PassthroughSubject<Int, NetworkError>()
        let operation = Task {
            try await NetworkManager.firstValue(subject.handleEvents(
                receiveSubscription: { _ in started.fulfill() },
                receiveCancel: { XCTAssertTrue(Thread.isMainThread); cancelled.fulfill() }
            ).eraseToAnyPublisher())
        }
        await fulfillment(of: [started], timeout: 3)
        operation.cancel()
        let result = try await operation.value
        XCTAssertNil(result)
        await fulfillment(of: [cancelled], timeout: 3)
        subject.send(1)
    }

    func testRawShareResponseCrossesOnlyAsDataToWorker() async throws {
        let started = expectation(description: "started")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let service = NetworkCoreShareService(network: network)
        let operation = Task.detached {
            try await service.artifactImage(cardID: "card", artifactID: "image")
        }
        await fulfillment(of: [started], timeout: 3)
        fixture.respond("synthetic-image-bytes", contentType: "image/png")
        let bytes = try await operation.value
        XCTAssertEqual(bytes, Data("synthetic-image-bytes".utf8))
        XCTAssertEqual(fixture.count, 1)
    }

    func testMergeRequestEncodingRetainsCanonicalBytesOutsideMainActor() async throws {
        let document = Data(#"{"schemaVersion":"card_doc.v1","blocks":[{"id":"blk_body","type":"paragraph","content":[{"type":"text","text":"retained body"}]}],"meta":{}}"#.utf8)
        let operation = Task.detached {
            let dto = try MergeArtifactSaveRequestDTO(baseRevision: 3, baseHash: "base",
                idemKey: "stable", documentJSON: document, tags: ["science"])
            let encoding = try NetworkManager.mergeArtifactEncoding(dto)
            XCTAssertFalse(Thread.isMainThread)
            let request = try encoding.encode(URLRequest(url: URL(string: "https://fixture.invalid/artifact")!), with: nil)
            XCTAssertEqual(request.httpBody, try dto.canonicalBody())
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["baseRevision"] as? Int, 3)
            XCTAssertEqual(body["idemKey"] as? String, "stable")
            XCTAssertEqual(body["tags"] as? [String], ["science"])
            XCTAssertNil(body["rate"])
        }
        try await operation.value
    }
}

extension XCTestCase {
    @MainActor
    func prepareLinkAuth() {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousToken = auth.authToken
        let previousAccess = auth.accessState
        let wasVerified = auth.canEnterProduct
        addTeardownBlock {
            await MainActor.run {
                if wasVerified, let user = previousUser, let token = previousToken, let access = previousAccess {
                    auth.saveUserSession(AuthResponse(success: true, message: nil, data: AuthResponseData(
                        token: token, user: user, isNewUser: false, productAccess: access)))
                } else if let user = previousUser, let token = previousToken {
                    auth.installUITestSession(token: token, actorID: user.id, email: user.email, username: user.username, createdAt: user.createdAt)
                } else {
                    auth.invalidateLocalSession()
                }
                auth.applyAccess(previousAccess ?? AccessState(mode: "", status: "", scope: nil, reasonCode: nil))
            }
        }
        auth.saveUserSession(AuthResponse(success: true, message: nil, data: AuthResponseData(
            token: "synthetic-link-token",
            user: User(id: "link_actor", username: "Link", email: "link@fixture.invalid",
                       avatar: nil, bio: nil, credit: 0, createdAt: "2026-11-21T00:00:00Z"),
            isNewUser: false,
            productAccess: AccessState(mode: "private_beta", status: "allowed", scope: "product_full", reasonCode: nil))))
        XCTAssertTrue(auth.canEnterProduct)
    }
}
