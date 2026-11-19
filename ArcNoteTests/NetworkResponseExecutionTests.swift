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
}
