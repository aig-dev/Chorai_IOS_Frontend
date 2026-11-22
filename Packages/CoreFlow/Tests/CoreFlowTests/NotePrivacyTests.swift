import XCTest
@testable import CoreFlow

@MainActor
final class NotePrivacyTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "owner", environmentID: "https://first.invalid")
    private let base = "vp1." + String(repeating: "A", count: 43)
    private let result = "vp1." + String(repeating: "E", count: 43)
    private let later = "vp1." + String(repeating: "I", count: 43)

    private func envelope(_ token: String, _ audience: String, receipt: [String: Any]? = nil) throws -> Data {
        var data: [String: Any] = ["current_policy": ["asset_id": "asset", "visibility": audience,
            "policy_token": token, "space_id": "workspace"]]
        data["visibility_receipt"] = receipt
        return try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
    }

    func testReopenAfterLostResponseMatchesOriginalReceiptAndUsesNewerOwnerPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = NotePrivacyJournal(directory: directory)
        let initial = try NotePrivacyWire.decode(status: 200, data: envelope(base, "WORKSPACE"), assetID: "asset")
        let request = try await journal.begin(scope: scope, path: "/assets/asset/visibility", observed: initial, desired: .PUBLIC)
        let reopened = NotePrivacyJournal(directory: directory)
        let recovered = try await reopened.pending(scope: scope, assetID: "asset")
        XCTAssertEqual(recovered, request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: request.bytes) as? [String: String])
        XCTAssertEqual(payload, ["visibility": "PUBLIC", "base_policy_token": base])
        for elsewhere in [NoteStoreScope(actorID: "other", environmentID: scope.environmentID),
                          NoteStoreScope(actorID: scope.actorID, environmentID: "https://second.invalid")] {
            let separate = try await reopened.pending(scope: elsewhere, assetID: "asset")
            XCTAssertNil(separate)
        }
        do { _ = try await reopened.begin(scope: scope, path: "/assets/asset/visibility", observed: initial, desired: .PRIVATE); XCTFail("Replaced pending decision") }
        catch NotePrivacyError.pendingCommand {}
        let receipt: [String: Any] = ["action": "SET_VISIBILITY", "client_request_id": request.requestID.uuidString,
            "actor_id": "owner", "asset_id": "asset", "requested_visibility": "PUBLIC", "requested_space_id": NSNull(),
            "base_policy_token": base, "result_policy_token": result, "activity_id": "activity", "action_log_id": "log"]
        let current = try NotePrivacyWire.decode(status: 200, data: envelope(later, "PRIVATE", receipt: receipt),
                                                assetID: "asset", command: request)
        XCTAssertEqual(current.audience, .PRIVATE)
        XCTAssertEqual(current.spaceID, "workspace")
        for field in receipt.keys {
            var wrong = receipt
            wrong[field] = "!"
            XCTAssertThrowsError(try NotePrivacyWire.decode(status: 200, data: envelope(later, "PRIVATE", receipt: wrong),
                                                           assetID: "asset", command: request), field)
        }
        XCTAssertThrowsError(try NotePrivacyWire.decode(status: 200, data: envelope(result, "PRIVATE", receipt: receipt),
                                                       assetID: "asset", command: request))
        try await reopened.settle(request)
        let cleared = try await journal.pending(scope: scope, assetID: "asset")
        XCTAssertNil(cleared)
    }

    func testOnlyVerifiedStaleResponseCanRetireAnAttempt() throws {
        for (status, code, expected) in [(409, "stale_policy", NotePrivacyError.stalePolicy),
            (409, "idempotency_conflict", .idempotencyConflict), (503, "action_outcome_unknown", .outcomeUnknown)] {
            let data = try JSONSerialization.data(withJSONObject: ["success": false,
                "error": ["reason": code, "code": code, "message": code]])
            XCTAssertThrowsError(try NotePrivacyWire.decode(status: status, data: data, assetID: "asset")) {
                XCTAssertEqual($0 as? NotePrivacyError, expected)
            }
        }
        let admission = Data(#"{"success":false,"error_code":"access_unavailable","message":"try later"}"#.utf8)
        XCTAssertThrowsError(try NotePrivacyWire.decode(status: 503, data: admission, assetID: "asset")) {
            XCTAssertEqual($0 as? NotePrivacyError, .admission("access_unavailable"))
        }
        XCTAssertThrowsError(try NotePrivacyWire.decode(status: 200, data: envelope("vp1.invalid", "PUBLIC"), assetID: "asset"))
    }
}
