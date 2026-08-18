import Foundation
import XCTest

final class CardEditorTagFocusSourceContractTests: XCTestCase {
    func testSharedTagRowUsesConfigurableSemanticsAndSharedCapsule() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        let presentation = try source(
            at: "ArcNote/CardEditor/CardMetadataPresentation.swift"
        )
        let row = try body(in: metadata, after: "struct CardEditorTagRow: View")
        let capsule = try body(
            in: presentation,
            after: "struct CardMetadataTagCapsule: View"
        )

        XCTAssertTrue(metadata.contains("struct CardEditorTagSemantics"))
        XCTAssertTrue(row.contains("let semantics: CardEditorTagSemantics"))
        XCTAssertTrue(row.contains("CardMetadataTagCapsule("))
        XCTAssertTrue(row.contains("semantics.tagIdentifierPrefix"))
        XCTAssertTrue(row.contains("semantics.addTagIdentifier"))
        XCTAssertTrue(row.contains("semantics.inputIdentifier"))
        XCTAssertTrue(row.contains("CardEditingTag.maximumCount"))
        XCTAssertFalse(row.contains("if isMerge"))
        XCTAssertFalse(row.contains("Circle().fill"))
        XCTAssertFalse(capsule.contains("Circle().fill"))
    }

    func testShellOwnsTagFocusAndInputConsumesItsBinding() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let input = try body(in: metadata, after: "struct CardEditorTagInput: View")

        XCTAssertTrue(
            shell.contains("@FocusState private var isTagInputFocused: Bool")
        )
        XCTAssertTrue(
            metadata.contains(
                "let isTagInputFocused: FocusState<Bool>.Binding"
            )
        )
        XCTAssertTrue(
            shell.contains("isTagInputFocused: $isTagInputFocused")
        )
        XCTAssertTrue(input.contains(".focused(isTagInputFocused)"))
        XCTAssertFalse(
            input.contains("@FocusState private var isTagInputFocused"),
            "The field must not isolate focus from its shell"
        )
    }

    func testShellUsesOneSemanticCompletionPathWithoutRootTapInterception() throws {
        let shellSource = try source(
            at: "ArcNote/CardEditor/CardEditorShell.swift"
        )
        let shell = try body(in: shellSource, after: "struct CardEditorShell: View")
        let completion = try body(
            in: String(shell),
            after: "private func completeTagEntry()"
        )

        XCTAssertTrue(completion.contains("guard isAddingTag else { return }"))
        XCTAssertTrue(completion.contains("isTagInputFocused = false"))
        XCTAssertTrue(completion.contains("onCompleteTag()"))
        XCTAssertFalse(
            completion.contains("bodyModel.dismissKeyboard()"),
            "Finishing a tag must not blur a body tap that reaches the WKWebView"
        )
        XCTAssertTrue(shell.contains("GeometryReader { viewport in"))
        XCTAssertTrue(
            shell.contains(
                ".frame(minHeight: viewport.size.height, alignment: .top)"
            )
        )
        XCTAssertTrue(shell.contains("CardEditorBlankTapSurface"))
        XCTAssertTrue(
            shell.contains(
                ".frame(minHeight: viewport.size.height, alignment: .top)\n"
                    + "                    .background {\n"
                    + "                        CardEditorBlankTapSurface"
            ),
            "The single blank-area tap owner must cover max(viewport, content)"
        )
        XCTAssertEqual(
            String(shell).components(separatedBy: "CardEditorBlankTapSurface(").count - 1,
            1,
            "Blank-area completion must have one behind-content owner"
        )
        XCTAssertTrue(shell.contains("onCompleteTag: completeTagEntry"))
        XCTAssertTrue(shell.contains("onInteraction: completeTagEntry"))
        XCTAssertFalse(
            shell.contains(".contentShape(Rectangle())\n        .simultaneousGesture"),
            "The root must not steal taps from child controls"
        )
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func body(in source: String, after marker: String) throws -> Substring {
        let markerRange = try XCTUnwrap(source.range(of: marker))
        let openingIndex = try XCTUnwrap(
            source[markerRange.upperBound...].firstIndex(of: "{")
        )
        var index = source.index(after: openingIndex)
        var depth = 1
        var isInString = false
        var isEscaped = false

        while index < source.endIndex {
            let character = source[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else if character == "\"" {
                isInString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return source[
                        source.index(after: openingIndex)..<index
                    ]
                }
            }
            index = source.index(after: index)
        }

        XCTFail("Unbalanced body after \(marker)")
        return ""
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
