import Foundation
import XCTest
@testable import CoreFlow

final class MergeArtifactDraftTests: XCTestCase {
    func testDraftSnapshotRoundTripsExactPendingOperationBytesAndIdentity() throws {
        let pendingDocument = Data(#"{"type":"doc","content":[{"id":"blk_pending"}]}"#.utf8)
        let currentDocument = Data(#"{"type":"doc","content":[{"id":"blk_current"}]}"#.utf8)
        let manifest = Data(#"{"preserved":["blk_current"]}"#.utf8)
        let pending = MergePendingArtifactSave(
            idempotencyKey: "merge-artifact-save-job-7-op-3",
            baseRevision: 7,
            baseDocumentHash: "sha256:revision-7",
            documentJSON: pendingDocument,
            tags: ["Design", "Research"]
        )
        let snapshot = MergeArtifactDraftSnapshot(
            baseRevision: 7,
            baseDocumentHash: "sha256:revision-7",
            documentJSON: currentDocument,
            tags: ["Design", "Research", "New"],
            rate: 3,
            preservationManifest: manifest,
            pendingSave: pending,
            validationRejection: MergeArtifactDraftValidationRejection(
                idempotencyKey: pending.idempotencyKey,
                code: "invalid_document"
            )
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MergeArtifactDraftSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.pendingSave?.idempotencyKey, pending.idempotencyKey)
        XCTAssertEqual(decoded.pendingSave?.documentJSON, pendingDocument)
        XCTAssertEqual(decoded.documentJSON, currentDocument)
        XCTAssertEqual(decoded.preservationManifest, manifest)
        XCTAssertEqual(
            decoded.validationRejection,
            MergeArtifactDraftValidationRejection(
                idempotencyKey: pending.idempotencyKey,
                code: "invalid_document"
            )
        )
    }

    func testLegacyDraftWithoutValidationRejectionDecodesAsRetryable() throws {
        let pendingDocument = Data(#"{"type":"doc","content":[]}"#.utf8)
        let snapshot = MergeArtifactDraftSnapshot(
            baseRevision: 4,
            baseDocumentHash: "sha256:revision-4",
            documentJSON: pendingDocument,
            tags: [],
            rate: 2,
            preservationManifest: Data(),
            pendingSave: MergePendingArtifactSave(
                idempotencyKey: "legacy-pending",
                baseRevision: 4,
                baseDocumentHash: "sha256:revision-4",
                documentJSON: pendingDocument,
                tags: []
            )
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "validationRejection")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            MergeArtifactDraftSnapshot.self,
            from: legacy
        )

        XCTAssertNil(decoded.validationRejection)
        XCTAssertEqual(decoded.pendingSave?.idempotencyKey, "legacy-pending")
    }
}
