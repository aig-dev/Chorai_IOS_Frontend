import CoreFlow
import XCTest

final class LibraryCardPreviewParserTests: XCTestCase {
    func testStructuredDocumentProvidesFirstSafeImageAndPlainText() {
        let document = #"[{"type":"paragraph","content":[{"type":"text","text":"Before","styles":{}}],"children":[]},{"type":"image","props":{"url":"/chorai-assets/staged/note_media/act_1/image.png","name":"Diagram"},"children":[]},{"type":"paragraph","content":[{"type":"text","text":"After","styles":{}}],"children":[]}]"#

        let preview = LibraryCardPreviewParser.parse(
            content: "stale fallback",
            contentJSON: document
        )

        XCTAssertEqual(
            preview.imageSource,
            "/chorai-assets/staged/note_media/act_1/image.png"
        )
        XCTAssertEqual(preview.imageAlternativeText, "Diagram")
        XCTAssertEqual(preview.text, "Before\nAfter")
    }

    func testStructuredDocumentSkipsUnsafeImageAndTraversesNestedBlocks() {
        let document = #"{"blocks":[{"type":"image","props":{"url":"javascript:alert(1)"},"children":[]},{"type":"paragraph","content":[],"children":[{"type":"image","props":{"src":"https://cdn.chorai.example/nested.webp","caption":"Nested image"},"children":[]}]}]}"#

        let preview = LibraryCardPreviewParser.parse(
            content: "fallback",
            contentJSON: document
        )

        XCTAssertEqual(
            preview.imageSource,
            "https://cdn.chorai.example/nested.webp"
        )
        XCTAssertEqual(preview.imageAlternativeText, "Nested image")
    }

    func testMarkdownFallbackExtractsLocalHTTPImageWithoutLeakingSyntax() {
        let preview = LibraryCardPreviewParser.parse(
            content: "Lead\n![Inline image](http://127.0.0.1:9000/chorai-assets/staged/note_media/act_1/image.png)\nTail"
        )

        XCTAssertEqual(
            preview.imageSource,
            "http://127.0.0.1:9000/chorai-assets/staged/note_media/act_1/image.png"
        )
        XCTAssertEqual(preview.imageAlternativeText, "Inline image")
        XCTAssertEqual(preview.text, "Lead\nTail")
        XCTAssertFalse(preview.text.contains("!["))
    }

    func testImageOnlyMarkdownProducesNoLiteralTextPreview() {
        let preview = LibraryCardPreviewParser.parse(
            content: "![Inline image](/chorai-assets/staged/image.png)"
        )

        XCTAssertEqual(preview.imageSource, "/chorai-assets/staged/image.png")
        XCTAssertEqual(preview.text, "")
    }

    func testCanonicalAssetPathWithoutLeadingSlashRemainsDisplayable() {
        let preview = LibraryCardPreviewParser.parse(
            content: "![Asset](chorai-assets/note_media/act_1/image.png)"
        )

        XCTAssertEqual(
            preview.imageSource,
            "chorai-assets/note_media/act_1/image.png"
        )
        XCTAssertEqual(preview.text, "")
    }

    func testHTMLFallbackExtractsImageAndRetainsReadableText() {
        let preview = LibraryCardPreviewParser.parse(
            content: #"<p>Hello</p><img src="https://cdn.chorai.example/image.jpg" alt="A landscape"><p>World</p>"#
        )

        XCTAssertEqual(
            preview.imageSource,
            "https://cdn.chorai.example/image.jpg"
        )
        XCTAssertEqual(preview.imageAlternativeText, "A landscape")
        XCTAssertEqual(preview.text, "Hello\nWorld")
    }

    func testMalformedStructuredDocumentFallsBackToMarkdown() {
        let preview = LibraryCardPreviewParser.parse(
            content: "![Fallback](https://cdn.chorai.example/fallback.png)",
            contentJSON: "{not-json"
        )

        XCTAssertEqual(
            preview.imageSource,
            "https://cdn.chorai.example/fallback.png"
        )
        XCTAssertEqual(preview.text, "")
    }

    func testInternalDocumentReferenceIsNeverShownAsNotePreview() {
        let preview = LibraryCardPreviewParser.parse(
            content: "doc://note/hash/5bae8ab616a074b9"
        )

        XCTAssertEqual(preview.text, "")
        XCTAssertNil(preview.imageSource)
    }
}
