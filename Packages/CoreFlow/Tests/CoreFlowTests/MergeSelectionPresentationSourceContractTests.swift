import Foundation
import XCTest

final class MergeSelectionPresentationSourceContractTests: XCTestCase {
    func testMergeSelectionUsesOneSafeAreaPrimaryAction() throws {
        let lifecycle = try source(at: "ArcNote/CoreFlow/MergeLifecycleViews.swift")
        let cards = try source(at: "ArcNote/MergeView.swift")

        XCTAssertTrue(lifecycle.contains("MergeSelectionPrimaryAction("))
        XCTAssertTrue(lifecycle.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(lifecycle.contains("count == 1 ? \"Merge 1 card\""))
        XCTAssertTrue(lifecycle.contains("\"Merge \\(count) cards\""))
        XCTAssertTrue(lifecycle.contains(".frame(maxWidth: .infinity, minHeight: 56)"))
        XCTAssertTrue(lifecycle.contains(".accessibilityIdentifier(\"merge.action\")"))
        XCTAssertFalse(lifecycle.contains("MergeSelectionActionBar"))
        XCTAssertFalse(lifecycle.contains("Text(\"Selected notes\")"))
        XCTAssertTrue(cards.contains("struct MergeCardView: View"))
        XCTAssertTrue(cards.contains("LibraryCardBackgroundSurface("))
        XCTAssertTrue(cards.contains("LibraryCardContentPreview("))
        XCTAssertTrue(cards.contains("Image(systemName: \"checkmark\")"))
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
