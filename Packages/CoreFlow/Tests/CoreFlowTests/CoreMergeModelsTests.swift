import XCTest
@testable import CoreFlow

final class CoreMergeModelsTests: XCTestCase {
    func testJobStatusClassifiesEveryCanonicalStateAndPreservesUnknown() throws {
        let running = ["CREATED", "PREPARING", "SNAPSHOT_READY", "PLANNED", "GENERATING"]

        XCTAssertTrue(running.allSatisfy { MergeJobStatus(serverValue: $0).isRunning })
        XCTAssertTrue(MergeJobStatus.artifactReady.isReady)
        XCTAssertTrue(MergeJobStatus.committing.isCommitting)
        XCTAssertTrue(MergeJobStatus.committedCard.isTerminal)
        XCTAssertEqual(MergeJobStatus(serverValue: "COMMITTED"), .committedCard)
        XCTAssertTrue(MergeJobStatus.committedBlock.isTerminal)
        XCTAssertTrue(MergeJobStatus.failed.isTerminal)
        XCTAssertTrue(MergeJobStatus.cancelled.isTerminal)
        XCTAssertFalse(MergeJobStatus.committing.canCancel)
        XCTAssertEqual(
            MergeJobStatus(serverValue: "FUTURE_STATE"),
            .unknown("FUTURE_STATE")
        )
        XCTAssertFalse(MergeJobStatus.unknown("FUTURE_STATE").canCancel)
        XCTAssertFalse(MergeJobStatus.unknown("FUTURE_STATE").canCommit)
        XCTAssertEqual(MergeJobStatus.snapshotReady.serverValue, "PREPARING")
        XCTAssertEqual(MergeJobStatus.committedCard.serverValue, "COMMITTED")

        let encoded = try JSONEncoder().encode(MergeJobStatus.unknown("FUTURE_STATE"))
        XCTAssertEqual(
            try JSONDecoder().decode(MergeJobStatus.self, from: encoded),
            .unknown("FUTURE_STATE")
        )
    }

    func testDynamicJSONRoundTripKeepsNestedArtifactProperties() throws {
        let value: MergeJSONValue = .object([
            "label": .string("Root"),
            "weight": .number(0.75),
            "visible": .bool(true),
            "children": .array([
                .object(["title": .string("Branch")]),
                .null
            ])
        ])

        let data = try JSONEncoder().encode(value)

        XCTAssertEqual(try JSONDecoder().decode(MergeJSONValue.self, from: data), value)
    }

    func testArtifactCarriesTypedPresentationAndRawDocumentFromV2Envelope() throws {
        let envelope = try JSONDecoder().decode(
            ArtifactV2Envelope.self,
            from: Data(
                #"{"schemaVersion":"merge_artifact.v2","artifactId":"mart_1","jobId":"mjob_1","latestRevision":2,"latestHash":"sha256:document","document":{"blocks":[],"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"},"presentation":{"schemaVersion":"merge_artifact_presentation.v1","tags":["Design","Nature"],"rate":3},"presentationHash":"sha256:presentation"}"#.utf8
            )
        )

        let artifact = MergeArtifact(
            artifactID: envelope.artifactID,
            jobID: envelope.jobID,
            capabilityID: "text_fusion",
            outputKind: .document,
            document: MergeDocument(
                schemaVersion: "card_doc.v1",
                title: nil,
                subtitle: nil,
                blocks: [],
                metadata: [:]
            ),
            fragments: [],
            metadata: [:],
            latestRevision: envelope.latestRevision,
            latestHash: envelope.latestHash,
            documentJSON: envelope.documentJSON,
            presentationHash: envelope.presentationHash,
            presentation: envelope.presentation
        )

        XCTAssertEqual(artifact.latestRevision, 2)
        XCTAssertEqual(artifact.latestHash, "sha256:document")
        XCTAssertEqual(artifact.documentJSON, envelope.documentJSON)
        XCTAssertEqual(artifact.presentationHash, "sha256:presentation")
        XCTAssertEqual(
            artifact.presentation,
            MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: ["Design", "Nature"],
                rate: 3
            )
        )
    }

    func testArtifactSaveContractCarriesDocumentAndTagsButNoEditableRate() {
        let document = Data(#"{"blocks":[],"meta":{},"schemaVersion":"card_doc.v1"}"#.utf8)
        let request = MergeArtifactSaveRequest(
            baseRevision: 2,
            baseHash: "sha256:document-2",
            idempotencyKey: "save-key",
            documentJSON: document,
            tags: ["Edited"]
        )
        let result = MergeArtifactSaveResult(
            artifactID: "mart_1",
            revision: 3,
            documentHash: "sha256:document-3",
            presentationHash: "sha256:presentation-3",
            presentation: MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: ["Edited"],
                rate: 3
            )
        )

        XCTAssertEqual(request.baseRevision, 2)
        XCTAssertEqual(request.baseHash, "sha256:document-2")
        XCTAssertEqual(request.idempotencyKey, "save-key")
        XCTAssertEqual(request.documentJSON, document)
        XCTAssertEqual(request.tags, ["Edited"])
        XCTAssertEqual(result.revision, 3)
        XCTAssertEqual(result.documentHash, "sha256:document-3")
        XCTAssertEqual(result.presentation.rate, 3)
    }

    func testOrderedSourcesKeepsAnchorAndFirstDistinctSelection() {
        let anchor = source("ast_anchor", preview: "Anchor")
        let ordered = MergeSourceOrdering.ordered(
            anchor: anchor,
            companions: [
                source("ast_b", preview: "B first"),
                source("ast_anchor", preview: "Duplicate anchor"),
                source("ast_a", preview: "A"),
                source("ast_b", preview: "B duplicate")
            ]
        )

        XCTAssertEqual(ordered.map(\.assetID), ["ast_anchor", "ast_b", "ast_a"])
        XCTAssertEqual(ordered[1].preview, "B first")
    }

    func testNewCardCommitTargetKeepsOnlySupportedFields() {
        let request = MergeCommitRequest(
            idempotencyKey: "commit-key",
            target: .newCard(spaceID: "space_1", titleOverride: "A title")
        )

        XCTAssertEqual(request.idempotencyKey, "commit-key")
        XCTAssertEqual(request.target.targetType, "new_card")
        XCTAssertEqual(request.target.spaceID, "space_1")
        XCTAssertEqual(request.target.titleOverride, "A title")
    }

    func testArtifactTextFallbackPreservesStructuredAndUnknownContent() {
        let document = MergeDocument(
            schemaVersion: "1.0",
            title: "Merged",
            subtitle: nil,
            blocks: [
                block(type: "heading", text: "A heading"),
                block(type: "paragraph", text: "A paragraph"),
                MergeBlock(
                    id: "list",
                    type: "bullet_list",
                    content: [],
                    properties: [:],
                    children: [block(type: "list_item", text: "One")]
                ),
                MergeBlock(
                    id: "mind",
                    type: "mindmap",
                    content: [],
                    properties: ["label": .string("Root idea")],
                    children: [
                        MergeBlock(
                            id: "child",
                            type: "node",
                            content: [],
                            properties: ["title": .string("Branch")],
                            children: []
                        )
                    ]
                ),
                MergeBlock(
                    id: "future",
                    type: "future_block",
                    content: [],
                    properties: ["summary": .string("Future text")],
                    children: []
                )
            ],
            metadata: [:]
        )

        XCTAssertEqual(
            document.plainText,
            "A heading\n\nA paragraph\n\n• One\n\nRoot idea\n  Branch\n\nFuture text"
        )
    }

    private func source(_ id: String, preview: String) -> MergeSource {
        MergeSource(assetID: id, versionID: nil, preview: preview)
    }

    private func block(type: String, text: String) -> MergeBlock {
        MergeBlock(
            id: nil,
            type: type,
            content: [MergeInline(type: "text", text: text, properties: [:])],
            properties: [:],
            children: []
        )
    }

    private struct ArtifactV2Envelope: Decodable {
        let artifactID: String
        let jobID: String
        let latestRevision: Int
        let latestHash: String
        let documentJSON: Data
        let presentationHash: String
        let presentation: MergeArtifactPresentation

        private enum CodingKeys: String, CodingKey {
            case artifactID = "artifactId"
            case jobID = "jobId"
            case latestRevision
            case latestHash
            case document
            case presentationHash
            case presentation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            artifactID = try container.decode(String.self, forKey: .artifactID)
            jobID = try container.decode(String.self, forKey: .jobID)
            latestRevision = try container.decode(Int.self, forKey: .latestRevision)
            latestHash = try container.decode(String.self, forKey: .latestHash)
            presentationHash = try container.decode(String.self, forKey: .presentationHash)
            presentation = try container.decode(
                MergeArtifactPresentation.self,
                forKey: .presentation
            )
            let document = try container.decode(MergeJSONValue.self, forKey: .document)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            documentJSON = try encoder.encode(document)
        }
    }
}
