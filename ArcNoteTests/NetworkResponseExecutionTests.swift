import XCTest
import Combine
import Alamofire
import CoreFlow
import os
@testable import ArcNote

@MainActor
final class NetworkResponseExecutionTests: XCTestCase {
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

    private func prepareLinkAuth() {
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
                    guard case .api(_, let code, _) = error else { return XCTFail("Expected recovery result") }
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
                    case .api(let code, _, _): actual = "api:\(code)"
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
