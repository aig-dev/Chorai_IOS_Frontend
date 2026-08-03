import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class AccessStoreTests: XCTestCase {
    func testCaptureAcceptsOnlyCanonicalJoinURL() {
        let service = AccessServiceStub()
        let codes = CodeMemoryStore()
        let store = AccessStore(service: service, codes: codes, hosts: ["chorai.com"])

        XCTAssertTrue(store.capture(URL(string: "https://chorai.com/join#code=CRAI-AAAA-BBBB")!))
        XCTAssertEqual(codes.load(), "CRAI-AAAA-BBBB")
        XCTAssertFalse(store.capture(URL(string: "https://evil.example/join#code=CRAI-EVIL-CODE")!))
        XCTAssertFalse(store.capture(URL(string: "https://chorai.com/join?code=CRAI-LEAK")!))
        XCTAssertFalse(store.capture(URL(string: "https://chorai.com/join#ref=WAITLIST01")!))
        XCTAssertFalse(store.capture(URL(string: "https://chorai.com/other#code=CRAI-OTHER")!))
    }

    func testSuccessfulClaimClearsPendingCodeAndAllowsProduct() async {
        let service = AccessServiceStub()
        service.claimResult = .success(
            ClaimResult(
                access: AccessState(
                    mode: "private_beta",
                    status: "allowed",
                    scope: "product_full",
                    reasonCode: nil
                ),
                cohort: "invited_beta"
            )
        )
        let codes = CodeMemoryStore()
        codes.save("CRAI-AAAA-BBBB")
        let store = AccessStore(service: service, codes: codes, hosts: ["chorai.com"])

        await store.claim()

        XCTAssertEqual(store.phase, .allowed)
        XCTAssertNil(codes.load())
        XCTAssertNil(store.pendingCode)
    }

    func testMalformedAllowedStateFailsClosed() async {
        let service = AccessServiceStub()
        service.stateResult = .success(
            AccessState(
                mode: "mystery",
                status: "allowed",
                scope: "product_full",
                reasonCode: nil
            )
        )
        let store = AccessStore(
            service: service,
            codes: CodeMemoryStore(),
            hosts: ["chorai.com"]
        )

        await store.load()

        XCTAssertEqual(store.phase, .failed)
    }

    func testClaimFailureKeepsCodeAndReusesAttemptKey() async {
        let service = AccessServiceStub()
        service.claimResult = .failure(AccessStubError.failed)
        let codes = CodeMemoryStore()
        codes.save("CRAI-AAAA-BBBB")
        let store = AccessStore(service: service, codes: codes, hosts: ["chorai.com"])

        await store.claim()
        await store.claim()

        XCTAssertEqual(store.phase, .required)
        XCTAssertEqual(codes.load(), "CRAI-AAAA-BBBB")
        XCTAssertEqual(service.claimInputs.count, 2)
        XCTAssertEqual(
            service.claimInputs[0].idempotencyKey,
            service.claimInputs[1].idempotencyKey
        )
        XCTAssertEqual(store.message, "We could not use that code. Check it and try again.")
    }

    func testReplacingCodeCreatesNewAttemptKey() async {
        let service = AccessServiceStub()
        service.claimResult = .failure(AccessStubError.failed)
        let codes = CodeMemoryStore()
        let store = AccessStore(service: service, codes: codes, hosts: ["chorai.com"])

        store.save("CRAI-AAAA-BBBB")
        await store.claim()
        store.save("CRAI-CCCC-DDDD")
        await store.claim()

        XCTAssertNotEqual(
            service.claimInputs[0].idempotencyKey,
            service.claimInputs[1].idempotencyKey
        )
    }
}

private enum AccessStubError: Error { case failed }

private final class AccessServiceStub: AccessServing, @unchecked Sendable {
    var stateResult: Result<AccessState, Error> = .success(
        AccessState(
            mode: "private_beta",
            status: "required",
            scope: nil,
            reasonCode: "grant_required"
        )
    )
    var claimResult: Result<ClaimResult, Error> = .failure(AccessStubError.failed)
    private(set) var claimInputs: [ClaimInput] = []

    func get() async throws -> AccessState { try stateResult.get() }

    func claim(_ input: ClaimInput) async throws -> ClaimResult {
        claimInputs.append(input)
        return try claimResult.get()
    }
}

private final class CodeMemoryStore: CodeStoring, @unchecked Sendable {
    private var value: String?

    func load() -> String? { value }
    func save(_ code: String) { value = code }
    func clear() { value = nil }
}
