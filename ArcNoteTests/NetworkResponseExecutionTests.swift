import XCTest
import Combine
import Alamofire
@testable import ArcNote

@MainActor
final class NetworkResponseExecutionTests: XCTestCase {
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
