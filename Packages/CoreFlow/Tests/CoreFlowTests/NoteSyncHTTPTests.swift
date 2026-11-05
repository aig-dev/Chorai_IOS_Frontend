import Foundation
import XCTest
@testable import CoreFlow

final class NoteSyncHTTPTests: XCTestCase {
    func testCloudTimestampsPreserveOriginalOrderingAcrossDownload() throws {
        let data = Data(#"{"success":true,"data":{"id":"note","owner_actor_id":"actor","sync_token":"body-v1","lifecycle":"active","content":"body","tags":[],"is_public":false,"created_at":"2026-01-01T08:00:00+08:00","updated_at":"2026-01-02T00:00:00.123456Z"}}"#.utf8)
        let card = try NoteSyncHTTP.snapshot(from: data, actorID: "actor")
        XCTAssertEqual(card.createdAt, Date(timeIntervalSince1970: 1767225600))
        XCTAssertEqual(try XCTUnwrap(card.updatedAt).timeIntervalSince1970, 1767312000.123456, accuracy: 0.001)
    }

    func testReadsBodyAndTokenFromSameOwnedCardEnvelope() throws {
        let data = Data(#"{"success":true,"data":{"id":"note","owner_actor_id":"actor","sync_token":"body-v1","lifecycle":"active","content":"body","content_json":"{\"blocks\":[]}","tags":["tag"],"is_public":true}}"#.utf8)
        let card = try NoteSyncHTTP.snapshot(from: data, actorID: "actor")
        XCTAssertEqual(card.syncToken, "body-v1"); XCTAssertEqual(card.body.content, "body")
        XCTAssertEqual(card.body.tags, ["tag"]); XCTAssertTrue(card.isPublic)
        XCTAssertThrowsError(try NoteSyncHTTP.snapshot(from: data, actorID: "different"))
    }

    func testMutationAcknowledgmentMustUseExplicitOriginalReceipt() throws {
        let data = Data(#"{"success":true,"data":{"sync_token":"latest-v9","sync_receipt":{"operation_id":"operation","asset_id":"note","sync_token":"committed-v2","note_document_version_id":"version2","lifecycle":"active"}}}"#.utf8)
        let receipt = try NoteSyncHTTP.receipt(from: data)
        XCTAssertEqual(receipt.syncToken, "committed-v2")
        XCTAssertThrowsError(try NoteSyncHTTP.receipt(from: Data(#"{"success":true,"data":{"id":"note","sync_token":"latest-v9"}}"#.utf8)))
    }

    func testFailuresPreservePermissionPreconditionAndConflictMeaning() {
        let cases: [(Int, String, NoteSyncFailure)] = [
            (401, "", .authenticationRequired), (403, "", .permissionDenied), (403, "account_restricted", .accountRestricted),
            (409, "stale_version", .staleVersion), (409, "idempotency_conflict", .idempotencyConflict),
            (409, "note_authority_changed", .staleVersion), (403, "note_authority_revoked", .authorityRevoked),
            (428, "precondition_required", .preconditionRequired), (503, "sync_not_ready", .notReady),
            (422, "unsupported_document", .unsupportedDocument), (409, "media_expired", .mediaExpired),
            (404, "", .notFound), (409, "unknown", .invalidResponse)
        ]
        for (status, reason, expected) in cases {
            let body = try! JSONSerialization.data(withJSONObject: ["error": ["reason": reason]])
            XCTAssertEqual(NoteSyncHTTP.failure(status: status, body: body, retryAfter: nil), expected)
        }
    }

    func testRetryAfterSecondsAndHTTPDateAreHonored() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(NoteSyncHTTP.failure(status: 429, body: Data(), retryAfter: "120", now: now), .transient(retryAfter: 120))
        XCTAssertEqual(NoteSyncHTTP.failure(status: 503, body: Data(), retryAfter: "Thu, 01 Jan 1970 00:02:00 GMT", now: now), .transient(retryAfter: 120))
        XCTAssertEqual(NoteSyncHTTP.failure(status: 500, body: Data(), retryAfter: "NaN", now: now), .transient(retryAfter: nil))
    }

    func testMissingTokenAndServerErrorCannotBecomeValidSnapshots() {
        for json in [#"{"success":true,"data":{"id":"note","owner_actor_id":"actor","content":"body","tags":[],"is_public":false}}"#, #"{"success":false,"data":null}"#] {
            XCTAssertThrowsError(try NoteSyncHTTP.snapshot(from: Data(json.utf8), actorID: "actor"))
        }
    }
}
