import CoreFlow
import XCTest

final class LibraryCardPreviewParserTests: XCTestCase {
    func testPersonalPreviewUsesTheFirstOwnedImageReferenceIncludingRefOnlyBlocks() {
        let doc = #"[{"type":"paragraph","children":[{"type":"image","props":{"media_ref":"med_0123456789abcdef","caption":"Field sketch"}}]},{"type":"image","props":{"url":"https://cdn.example/second.png","caption":"Next photo"}}]"#
        let personal = LibraryCardPreviewParser.parse(content: "", contentJSON: doc, allowsLocalImages: true)
        XCTAssertEqual(personal.imageMediaRef, "med_0123456789abcdef")
        XCTAssertEqual(personal.imageAlternativeText, "Field sketch")
        let publicPreview = LibraryCardPreviewParser.parse(content: "", contentJSON: doc)
        XCTAssertNil(publicPreview.imageMediaRef)
        XCTAssertEqual(publicPreview.imageSource, "https://cdn.example/second.png")
        XCTAssertEqual(publicPreview.imageAlternativeText, "Next photo")
    }

    func testOwnedImagePreviewAcceptsOnlyCanonicalNoteAttachmentURLs() throws {
        let url = try NoteAttachmentFiles.previewURL(uploadID: "photo-1")
        func parse(_ source: String, owned: Bool) -> LibraryCardPreviewContent {
            let document = #"[{"type":"image","props":{"url":"\#(source)","name":"Camera"}}]"#
            return LibraryCardPreviewParser.parse(content: "", contentJSON: document, allowsLocalImages: owned)
        }
        XCTAssertEqual(parse(url.absoluteString, owned: true).imageSource, url.absoluteString)
        XCTAssertNil(parse(url.absoluteString, owned: false).imageSource)
        XCTAssertNil(parse(url.absoluteString + "?other=1", owned: true).imageSource)
        XCTAssertNil(parse("file:///tmp/photo.jpg", owned: true).imageSource)
    }

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
