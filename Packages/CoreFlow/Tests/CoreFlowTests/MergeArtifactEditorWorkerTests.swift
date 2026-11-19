import XCTest
@testable import CoreFlow

@MainActor
final class MergeArtifactEditorWorkerTests: XCTestCase {
    func testCleanDraftAndEditorProjectionReuseOneOffMainDecode() async throws {
        let decoded = MergeWorkerThreadProbe()
        let worker = MergeArtifactEditorWorker(beforeWork: nil, decodeProbe: { decoded.record() })
        let artifact = validArtifact()
        let clean = try await worker.cleanDraft(from: artifact)
        let projection = try await worker.project(cardDocumentJSON: artifact.documentJSON,
            displayURLsByMediaReference: [:])
        XCTAssertEqual(clean.documentJSON, artifact.documentJSON)
        XCTAssertEqual(clean.baseRevision, artifact.latestRevision)
        XCTAssertEqual(clean.baseDocumentHash, artifact.latestHash)
        XCTAssertEqual(clean.preservationManifest, projection.editable.preservationManifest)
        XCTAssertNil(clean.pendingSave)
        XCTAssertEqual(decoded.mainThreadValues, [false])
    }

    func testOversizedDecodeIsNotRetainedAndMalformedCanonicalKeepsOriginalBody() async throws {
        let decoded = MergeWorkerThreadProbe()
        let worker = MergeArtifactEditorWorker(beforeWork: nil, decodeProbe: { decoded.record() }, cacheByteLimit: 1)
        let artifact = validArtifact()
        _ = try await worker.cleanDraft(from: artifact)
        _ = try await worker.project(cardDocumentJSON: artifact.documentJSON, displayURLsByMediaReference: [:])
        XCTAssertEqual(decoded.mainThreadValues, [false, false])
        let invalid = MergeArtifact(artifactID: artifact.artifactID, jobID: artifact.jobID,
            capabilityID: artifact.capabilityID, outputKind: artifact.outputKind, document: artifact.document,
            fragments: artifact.fragments, metadata: artifact.metadata, latestRevision: artifact.latestRevision,
            latestHash: artifact.latestHash, documentJSON: Data("{}".utf8),
            presentationHash: artifact.presentationHash, presentation: artifact.presentation)
        let clean = try await worker.cleanDraft(from: invalid)
        XCTAssertEqual(clean.documentJSON, invalid.documentJSON)
        XCTAssertTrue(clean.preservationManifest.isEmpty)
    }

    func testProjectionAndEncodingMatchCodecOutsideMainThread() async throws {
        let probe = MergeWorkerThreadProbe()
        let worker = MergeArtifactEditorWorker(beforeWork: nil, probe: { probe.record() })
        let input = Data(#"{"schemaVersion":"card_doc.v1","meta":{"producer":"test"},"blocks":[{"id":"blk_test","type":"paragraph","content":[{"type":"text","text":"Original"}]}]}"#.utf8)
        let expected = try MergeArtifactEditorCodec.decode(cardDocumentJSON: input)
        let projected = try await worker.project(cardDocumentJSON: input, displayURLsByMediaReference: [:])
        XCTAssertEqual(projected.editable, expected)
        let prepared = try await worker.prepareDraft(blockNoteJSON: expected.blockNoteJSON,
            preserving: expected.preservationManifest, displayURLsByMediaReference: [:])
        XCTAssertEqual(prepared.documentJSON, try MergeArtifactEditorCodec.encode(blockNoteJSON: expected.blockNoteJSON,
            preserving: expected.preservationManifest))
        XCTAssertEqual(probe.mainThreadValues, [false, false])
    }

    func testURLValidationAndUnresolvedReferencesSharePreparedProjection() async throws {
        let worker = MergeArtifactEditorWorker()
        let input = Data(#"{"schemaVersion":"card_doc.v1","meta":{},"blocks":[{"id":"blk_image","type":"image","props":{"mediaRef":"med_1111111111111111","alignment":"center","origin":"source_image","prominence":"wide","semanticRole":"evidence"}}]}"#.utf8)
        let urls = ["med_1111111111111111": "https://example.com/image", "bad": "file:///secret", "credentials": "https://u:p@example.com/image"]
        let value = try await worker.project(cardDocumentJSON: input, displayURLsByMediaReference: urls)
        XCTAssertEqual(value.displayURLsByMediaReference, ["med_1111111111111111": "https://example.com/image"])
        XCTAssertTrue(value.unresolvedMediaReferences.isEmpty)
        let missing = try await worker.prepareDraft(blockNoteJSON: value.editable.blockNoteJSON,
            preserving: value.editable.preservationManifest, displayURLsByMediaReference: [:])
        XCTAssertEqual(missing.unresolvedMediaReferences, ["med_1111111111111111"])
    }

    func testUnsupportedOrLossyInputDoesNotProduceDraft() async throws {
        let worker = MergeArtifactEditorWorker()
        do {
            _ = try await worker.project(cardDocumentJSON: Data("{}".utf8), displayURLsByMediaReference: [:])
            XCTFail("Invalid source projected")
        } catch { XCTAssertEqual(error as? MergeArtifactEditorCodecError, .invalidCardDocument) }
        do {
            _ = try await worker.prepareDraft(blockNoteJSON: "[]", preserving: Data(), displayURLsByMediaReference: [:])
            XCTFail("Missing manifest accepted")
        } catch { XCTAssertEqual(error as? MergeArtifactEditorCodecError, .losslessRoundTripFailed) }
    }

    private func validArtifact() -> MergeArtifact {
        let base = makeMergeArtifact()
        return MergeArtifact(artifactID: base.artifactID, jobID: base.jobID,
            capabilityID: base.capabilityID, outputKind: base.outputKind, document: base.document,
            fragments: base.fragments, metadata: base.metadata, latestRevision: base.latestRevision,
            latestHash: base.latestHash,
            documentJSON: Data(String(decoding: base.documentJSON, as: UTF8.self)
                .replacingOccurrences(of: "block_1", with: "blk_test").utf8),
            presentationHash: base.presentationHash, presentation: base.presentation)
    }
}

private final class MergeWorkerThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func record() { lock.lock(); values.append(Thread.isMainThread); lock.unlock() }
    var mainThreadValues: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
}
