import XCTest
@testable import CoreFlow

final class CoreMergeModelsTests: XCTestCase {
    func testJobStatusClassifiesEveryCanonicalStateAndPreservesUnknown() throws {
        let running = ["CREATED", "SNAPSHOT_READY", "PLANNED", "GENERATING"]

        XCTAssertTrue(running.allSatisfy { MergeJobStatus(serverValue: $0).isRunning })
        XCTAssertTrue(MergeJobStatus.artifactReady.isReady)
        XCTAssertTrue(MergeJobStatus.committing.isCommitting)
        XCTAssertTrue(MergeJobStatus.committedCard.isTerminal)
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
}
