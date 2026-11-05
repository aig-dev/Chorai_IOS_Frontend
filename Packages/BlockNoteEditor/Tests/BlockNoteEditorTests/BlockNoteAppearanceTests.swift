import Foundation
import XCTest
@testable import BlockNoteEditor

final class BlockNoteAppearanceTests: XCTestCase {
    func testBothSystemAppearancesKeepDefaultTextReadable() {
        XCTAssertGreaterThan(contrast(0x1C1C1E, 0xFAF9F6), 7)
        XCTAssertGreaterThan(contrast(0xF5F5F7, 0x242329), 7)
        let css = BlockNoteEditorAppearance.stylesheet
        XCTAssertTrue(css.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(css.contains("--chorai-editor-ink: #1c1c1e"))
        XCTAssertTrue(css.contains("--chorai-editor-ink: #f5f5f7"))
        XCTAssertTrue(css.contains("caret-color: var(--chorai-editor-ink)"))
    }

    func testAppearanceDoesNotReplaceTheDocumentOrIssueEditorCommands() {
        let script = BlockNoteEditorAppearance.installationScript
        XCTAssertTrue(script.contains("createElement('style')"))
        XCTAssertTrue(script.contains("chorai-native-appearance"))
        XCTAssertFalse(script.contains("innerHTML"))
        XCTAssertFalse(script.contains("receiveCommand"))
        XCTAssertFalse(script.contains("contenteditable"))
    }

    func testWritingSpacingMatchesTheApprovedTextWhileMergeStaysCompact() {
        let writing = BlockNoteEditorAppearance.installationScript(fontScale: 23.0 / 17.0)
        let compact = BlockNoteEditorAppearance.installationScript(fontScale: 1)
        XCTAssertTrue(writing.contains("setProperty('--chorai-editor-block-gap', '29px')"))
        XCTAssertTrue(writing.contains("setProperty('--chorai-editor-line-height', '1.66')"))
        XCTAssertTrue(compact.contains("setProperty('--chorai-editor-block-gap', '16px')"))
        XCTAssertTrue(compact.contains("setProperty('--chorai-editor-line-height', '1.55')"))
        XCTAssertTrue(BlockNoteEditorAppearance.stylesheet.contains("margin-top: var(--chorai-editor-block-gap)"))
        XCTAssertTrue(BlockNoteEditorAppearance.stylesheet.contains("[data-content-type=paragraph] .bn-inline-content"))
        XCTAssertFalse(writing.contains("receiveCommand"))
        XCTAssertFalse(compact.contains("receiveCommand"))
    }

    func testWritingFloorIsExplicitAndCompactAppearanceDoesNotFillThePage() {
        let writing = BlockNoteEditorAppearance.installationScript(
            fontScale: 23.0 / 17.0, minimumWritingHeight: 520
        )
        let compact = BlockNoteEditorAppearance.installationScript(fontScale: 1)
        XCTAssertTrue(writing.contains("setProperty('--chorai-editor-writing-height', '520.0px')"))
        XCTAssertTrue(compact.contains("setProperty('--chorai-editor-writing-height', '0.0px')"))
        XCTAssertTrue(BlockNoteEditorAppearance.stylesheet.contains("box-sizing: border-box"))
        XCTAssertTrue(BlockNoteEditorAppearance.stylesheet.contains("min-height: var(--chorai-editor-writing-height, 0px)"))
        XCTAssertFalse(BlockNoteEditorAppearance.stylesheet.contains("100vh"),
                       "The content height must not depend on the content-sized WebView viewport")
        XCTAssertEqual(BlockNoteEditorAppearance.normalizedMinimumWritingHeight(.infinity), 0)
        XCTAssertEqual(BlockNoteEditorAppearance.normalizedMinimumWritingHeight(.nan), 0)
        XCTAssertEqual(BlockNoteEditorAppearance.normalizedMinimumWritingHeight(-10), 0)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ color: UInt32) -> Double {
            let components: [Double] = [16, 8, 0].map { Double((color >> $0) & 255) / 255.0 }
            let channels: [Double] = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
