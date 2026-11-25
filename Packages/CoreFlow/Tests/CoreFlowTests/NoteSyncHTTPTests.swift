import Foundation
import XCTest
@testable import CoreFlow

final class NoteSyncHTTPTests: XCTestCase {
    func testOwnerBackgroundRevisionIsOptionalAndBounded() throws {
        func decode(_ value: String?) throws -> NoteRemoteSnapshot {
            let field = value.map { ",\"background_revision\":" + $0 } ?? ""
            let bytes = Data("""
            {"success":true,"data":{"id":"note","owner_actor_id":"actor","sync_token":"v1","lifecycle":"active","content":"body","tags":[],"is_public":false\(field)}}
            """.utf8)
            return try NoteSyncHTTP.snapshot(from: bytes, actorID: "actor")
        }
        XCTAssertNil(try decode(nil).backgroundRevision)
        XCTAssertEqual(try decode("0").backgroundRevision, 0)
        XCTAssertEqual(try decode("9007199254740991").backgroundRevision, NoteBackgroundCommand.maxRevision)
        for value in ["-1", "true", "\"3\"", "1.5", "9007199254740992"] {
            XCTAssertThrowsError(try decode(value))
        }
        let historical = OfflineNote(localID: "legacy", body: .init(content: "kept"))
        let reopened = try JSONDecoder().decode(OfflineNote.self, from: JSONEncoder().encode(historical))
        XCTAssertNil(reopened.backgroundRevision)
        XCTAssertEqual(reopened.body, historical.body)
    }

    func testInvalidAuthoredTimestampRejectsSnapshotWithoutChangingMissingTimeSupport() throws {
        for value in ["not-a-date", "2026-01-01T00:00:60Z"] {
            let data = Data("""
            {"success":true,"data":{"id":"note","owner_actor_id":"actor","sync_token":"v1","lifecycle":"active","content":"body","tags":[],"is_public":false,"updated_at":"\(value)"}}
            """.utf8)
            XCTAssertThrowsError(try NoteSyncHTTP.snapshot(from: data, actorID: "actor")) {
                XCTAssertEqual($0 as? NoteSyncFailure, .invalidResponse)
            }
        }
        let missing = Data(#"{"success":true,"data":{"id":"note","owner_actor_id":"actor","sync_token":"v1","lifecycle":"active","content":"body","tags":[],"is_public":false}}"#.utf8)
        let snapshot = try NoteSyncHTTP.snapshot(from: missing, actorID: "actor")
        XCTAssertNil(snapshot.createdAt)
        XCTAssertNil(snapshot.updatedAt)
    }

    func testPageUsesTheSingleCardOwnerAndBodyChecksForEveryItem() throws {
        let mine: [String: Any] = ["id": "mine", "owner_actor_id": "owner", "sync_token": "v7", "lifecycle": "active",
                                   "content": "owned body", "content_json": #"{"blocks":[]}"#, "tags": ["test"], "is_public": false]
        var other = mine
        other["owner_actor_id"] = "elsewhere"
        func data(_ cards: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["success": true, "data": cards])
        }
        let page = try NoteSyncHTTP.snapshots(from: data([mine]), actorID: "owner")
        let single = try JSONSerialization.data(withJSONObject: ["success": true, "data": mine])
        XCTAssertEqual(page, [try NoteSyncHTTP.snapshot(from: single, actorID: "owner")])
        XCTAssertThrowsError(try NoteSyncHTTP.snapshots(from: data([mine, other]), actorID: "owner"))
        var missingToken = mine
        missingToken.removeValue(forKey: "sync_token")
        XCTAssertThrowsError(try NoteSyncHTTP.snapshots(from: data([mine, missingToken]), actorID: "owner"))
    }

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

    func testServiceNotReadyPreservesItsAdvertisedRetryDelay() {
        let body = Data(#"{"error":{"reason":"sync_not_ready"}}"#.utf8)
        XCTAssertEqual(NoteSyncHTTP.failure(status: 503, body: body, retryAfter: "60"), .transient(retryAfter: 60))
        XCTAssertEqual(NoteSyncHTTP.failure(status: 503, body: body, retryAfter: "invalid"), .notReady)
    }

    func testMissingTokenAndServerErrorCannotBecomeValidSnapshots() {
        for json in [#"{"success":true,"data":{"id":"note","owner_actor_id":"actor","content":"body","tags":[],"is_public":false}}"#, #"{"success":false,"data":null}"#] {
            XCTAssertThrowsError(try NoteSyncHTTP.snapshot(from: Data(json.utf8), actorID: "actor"))
        }
    }
}
