import Foundation
import XCTest
@testable import CoreFlow

final class MergeArtifactEditorCodecTests: XCTestCase {
    func testRichTaskTwoFixtureRoundTripsEverySupportedSemanticAndServerField() throws {
        let decoded = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(Self.richCardDocument.utf8)
        )
        let blocks = try blockNoteBlocks(decoded.blockNoteJSON)

        XCTAssertEqual(blocks.map { $0["id"] as? String }, [
            "blk_rich_heading",
            "blk_rich_paragraph",
            "blk_rich_bullet",
            "blk_rich_check",
            "blk_rich_image",
            "blk_rich_quote",
            "blk_rich_code",
            "blk_rich_divider",
        ])

        let heading = try XCTUnwrap(blocks[0] as NSDictionary)
        XCTAssertEqual(heading["type"] as? String, "heading")
        XCTAssertEqual((heading["props"] as? [String: Any])?["level"] as? Int, 2)
        let headingContent = try XCTUnwrap(heading["content"] as? [[String: Any]])
        XCTAssertEqual((headingContent[0]["styles"] as? [String: Any])?["bold"] as? Bool, true)

        let paragraphContent = try XCTUnwrap(blocks[1]["content"] as? [[String: Any]])
        XCTAssertEqual((paragraphContent[1]["styles"] as? [String: Any])?["italic"] as? Bool, true)
        XCTAssertEqual(paragraphContent[2]["type"] as? String, "link")
        XCTAssertEqual(paragraphContent[2]["href"] as? String, "https://example.com/reference")

        XCTAssertEqual(blocks[2]["type"] as? String, "bulletListItem")
        let bulletChildren = try XCTUnwrap(blocks[2]["children"] as? [[String: Any]])
        let firstBulletChild = try XCTUnwrap(bulletChildren.first)
        let firstBulletChildID: String? = firstBulletChild["id"] as? String
        XCTAssertEqual(firstBulletChildID, "blk_rich_child")
        XCTAssertEqual(blocks[3]["type"] as? String, "checkListItem")
        XCTAssertEqual((blocks[3]["props"] as? [String: Any])?["checked"] as? Bool, true)

        XCTAssertEqual(blocks[4]["type"] as? String, "image")
        let imageProps = try XCTUnwrap(blocks[4]["props"] as? [String: Any])
        XCTAssertEqual(imageProps["mediaRef"] as? String, "med_1111111111111111")
        XCTAssertEqual(imageProps["previewWidth"] as? Int, 960)
        XCTAssertEqual(imageProps["textAlignment"] as? String, "center")

        XCTAssertTrue(decoded.fallbackMarkdown.contains("Rich heading"))
        XCTAssertTrue(decoded.fallbackMarkdown.contains("Nested detail"))

        let encoded = try MergeArtifactEditorCodec.encode(
            blockNoteJSON: decoded.blockNoteJSON,
            preserving: decoded.preservationManifest
        )
        XCTAssertEqual(encoded, Data(Self.richCardDocument.utf8))
    }

    func testGovernedHTTPLinkRoundTripsAndMailtoFailsClosed() throws {
        let httpDocument = Self.document(
            blocks: #"[{"content":[{"content":[{"text":"reference","type":"text"}],"href":"http://example.com:8080/reference","type":"link"}],"id":"blk_http_link","type":"paragraph"}]"#
        )
        let decoded = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(httpDocument.utf8)
        )
        XCTAssertEqual(
            try MergeArtifactEditorCodec.encode(
                blockNoteJSON: decoded.blockNoteJSON,
                preserving: decoded.preservationManifest
            ),
            Data(httpDocument.utf8)
        )

        let mailtoDocument = Self.document(
            blocks: #"[{"content":[{"content":[{"text":"email","type":"text"}],"href":"mailto:person@example.com","type":"link"}],"id":"blk_mailto_link","type":"paragraph"}]"#
        )
        XCTAssertThrowsError(
            try MergeArtifactEditorCodec.decode(
                cardDocumentJSON: Data(mailtoDocument.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? MergeArtifactEditorCodecError, .invalidCardDocument)
        }
    }

    func testDeletingPassthroughBlockFailsLosslessRoundTrip() throws {
        let decoded = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(Self.richCardDocument.utf8)
        )
        var blocks = try blockNoteBlocks(decoded.blockNoteJSON)
        blocks.removeAll { $0["id"] as? String == "blk_rich_quote" }

        assertLosslessFailure(
            blockNoteJSON: try jsonString(blocks),
            manifest: decoded.preservationManifest
        )
    }

    func testMutatingPassthroughBlockFailsLosslessRoundTrip() throws {
        let decoded = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(Self.richCardDocument.utf8)
        )
        var blocks = try blockNoteBlocks(decoded.blockNoteJSON)
        guard let quoteIndex = blocks.firstIndex(where: {
            $0["id"] as? String == "blk_rich_quote"
        }) else {
            return XCTFail("Expected the quote passthrough block")
        }
        blocks[quoteIndex]["content"] = [[
            "styles": [String: Any](),
            "text": "mutated",
            "type": "text",
        ]]

        assertLosslessFailure(
            blockNoteJSON: try jsonString(blocks),
            manifest: decoded.preservationManifest
        )
    }

    func testMovingPassthroughBlockFailsLosslessRoundTrip() throws {
        let decoded = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(Self.richCardDocument.utf8)
        )
        var blocks = try blockNoteBlocks(decoded.blockNoteJSON)
        let quote = blocks.remove(at: 5)
        blocks.insert(quote, at: 0)

        assertLosslessFailure(
            blockNoteJSON: try jsonString(blocks),
            manifest: decoded.preservationManifest
        )
    }

    func testDuplicatingPassthroughBlockFailsLosslessRoundTrip() throws {
        let decoded = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(Self.richCardDocument.utf8)
        )
        var blocks = try blockNoteBlocks(decoded.blockNoteJSON)
        let quote = blocks[5]
        blocks.append(quote)

        assertLosslessFailure(
            blockNoteJSON: try jsonString(blocks),
            manifest: decoded.preservationManifest
        )
    }

    private func assertLosslessFailure(
        blockNoteJSON: String,
        manifest: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try MergeArtifactEditorCodec.encode(
                blockNoteJSON: blockNoteJSON,
                preserving: manifest
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? MergeArtifactEditorCodecError,
                .losslessRoundTripFailed,
                file: file,
                line: line
            )
        }
    }

    private func blockNoteBlocks(_ json: String) throws -> [[String: Any]] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )
    }

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private static func document(blocks: String) -> String {
        #"{"blocks":\#(blocks),"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#
    }

    private static let richCardDocument = #"{"blocks":[{"content":[{"styles":{"bold":true},"text":"Rich heading","type":"text"}],"id":"blk_rich_heading","props":{"level":2},"type":"heading"},{"content":[{"text":"Plain ","type":"text"},{"styles":{"italic":true},"text":"italic ","type":"text"},{"content":[{"styles":{"underline":true},"text":"reference","type":"text"}],"href":"https://example.com/reference","type":"link"}],"id":"blk_rich_paragraph","type":"paragraph"},{"children":[{"content":[{"text":"Nested detail","type":"text"}],"id":"blk_rich_child","type":"paragraph"}],"content":[{"text":"Parent item","type":"text"}],"id":"blk_rich_bullet","type":"bullet_list"},{"content":[{"styles":{"strike":true},"text":"Completed","type":"text"}],"id":"blk_rich_check","props":{"checked":true},"type":"checklist"},{"id":"blk_rich_image","props":{"alignment":"center","mediaRef":"med_1111111111111111","origin":"source_image","prominence":"wide","semanticRole":"evidence"},"type":"image"},{"content":[{"text":"Preserve quote","type":"text"}],"id":"blk_rich_quote","type":"quote"},{"content":[{"text":"let exact = true","type":"text"}],"id":"blk_rich_code","type":"code"},{"content":[],"id":"blk_rich_divider","type":"divider"}],"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#
}
