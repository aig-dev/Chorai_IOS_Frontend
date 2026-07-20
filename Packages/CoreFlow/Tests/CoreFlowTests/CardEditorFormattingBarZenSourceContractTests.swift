import Foundation
import XCTest

final class CardEditorFormattingBarZenSourceContractTests: XCTestCase {
    func testPhotoIsFixedBeforeTagAndOnlyScrollableCommandsRenderInTheStrip() throws {
        let formatting = try source(
            at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
        )
        let body = try section(
            of: formatting,
            from: "var body: some View {",
            to: "private func commandButton("
        )
        let scroll = try section(
            of: String(body),
            from: "ScrollView(.horizontal",
            to: ".padding(.horizontal, 10)"
        )
        let commandButton = try section(
            of: formatting,
            from: "private func commandButton(",
            to: "private func isSelected("
        )

        let fixedPhoto = try XCTUnwrap(
            body.range(of: "commandButton(.inlineImage)")
        )
        let addTag = try XCTUnwrap(
            body.range(of: "cardEditorAddTag")
        )
        XCTAssertLessThan(fixedPhoto.lowerBound, addTag.lowerBound)
        XCTAssertEqual(
            String(body).components(
                separatedBy: "commandButton(.inlineImage)"
            ).count - 1,
            1,
            "Photo must render exactly once in the toolbar body"
        )
        XCTAssertFalse(
            scroll.contains("commandButton(.inlineImage)"),
            "Photo must stay outside the horizontally scrolling strip"
        )

        let commandList = try section(
            of: formatting,
            from: "static let scrollableCommands",
            to: "var id: String"
        )
        XCTAssertFalse(commandList.contains(".inlineImage"))
        XCTAssertTrue(
            scroll.contains(
                "ForEach(CardEditorFormattingCommand.scrollableCommands)"
            )
        )
        XCTAssertFalse(
            scroll.contains("ForEach(CardEditorFormattingCommand.allCases)")
        )
        XCTAssertFalse(body.contains("cardEditorKeyboardDismiss"))
        XCTAssertFalse(body.contains("keyboard.chevron.compact.down"))
        XCTAssertTrue(
            body.contains("ZenVisualTokens.background.opacity(0.78)"),
            "Formatting chrome must quiet content bleed without changing global glass"
        )
        XCTAssertTrue(
            commandButton.contains("frame(minWidth: 45, minHeight: 44)"),
            "Every formatting command must retain its 45x44 hit target"
        )
    }

    private func section(
        of source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(
            source.range(
                of: endMarker,
                range: start.upperBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
