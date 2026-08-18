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
            pendingSave: pending
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MergeArtifactDraftSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.pendingSave?.idempotencyKey, pending.idempotencyKey)
        XCTAssertEqual(decoded.pendingSave?.documentJSON, pendingDocument)
        XCTAssertEqual(decoded.documentJSON, currentDocument)
        XCTAssertEqual(decoded.preservationManifest, manifest)
    }
}
