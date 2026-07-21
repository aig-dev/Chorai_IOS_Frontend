import Foundation
import XCTest

final class SparkContinuationSourceContractTests: XCTestCase {
    func testSparkPopupContinuesTheActiveSessionInsteadOfPushingAnotherScreen() throws {
        let popup = try source(at: "ArcNote/PopupMenuView.swift")
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )

        XCTAssertTrue(
            popup.contains("let onSpark: (() -> Void)?"),
            "The shared popup needs an optional screen-scoped Spark action"
        )
        XCTAssertTrue(
            popup.contains("let isSparkEnabled: Bool"),
            "A scoped Spark action must be suppressible outside the loaded phase"
        )
        XCTAssertTrue(
            popup.contains("if let onSpark"),
            "A scoped Spark action must win over the global navigation fallback"
        )
        XCTAssertTrue(popup.contains("isEnabled: isSparkEnabled"))
        XCTAssertTrue(popup.contains("onSpark()"))
        XCTAssertTrue(
            continuation.contains("onSpark: store.sparkCurrentDeeper"),
            "Spark results must continue through the current session store"
        )
        XCTAssertTrue(
            continuation.contains("isSparkEnabled: store.phase == .loaded")
        )
    }

    func testPendingContinuationAppearsAsTheNextNumberedHistoryNode() throws {
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )

        XCTAssertTrue(continuation.contains("ForEach(displayedNodes)"))
        XCTAssertTrue(
            continuation.contains("nodes.prefix(through: activeIndex)"),
            "A branch must hide descendants that the successful trigger replaces"
        )
        XCTAssertTrue(
            continuation.contains("Text(\"\\(pendingDepth + 1)\")"),
            "The pending child number must derive from the active parent depth"
        )
        XCTAssertFalse(continuation.contains("Text(\"\\(nodes.count + 1)\")"))
        XCTAssertTrue(
            continuation.contains(
                ".accessibilityIdentifier(\"spark.chain.pending\")"
            )
        )
    }

    func testSparkResultCardUsesTheFlowCardPresentationLanguage() throws {
        let card = try sparkResultCardSource()

        XCTAssertFalse(
            card.contains("result.card.title"),
            "Spark cards must not resurrect the title removed from Flow cards"
        )
        XCTAssertTrue(
            card.contains("Button(action: onSparkDeeper)"),
            "Touch users need the same direct Spark action exposed by Flow cards"
        )
        XCTAssertTrue(
            card.contains(
                ".accessibilityIdentifier(\"spark.continue.\\(result.id)\")"
            )
        )
        XCTAssertFalse(
            card.contains(
                ".accessibilityAction(named: Text(\"Spark deeper\"), onSparkDeeper)"
            ),
            "A failed card must not advertise a guarded no-op accessibility action"
        )
        XCTAssertTrue(
            card.contains("SparkDeeperAccessibilityActionModifier("),
            "The accessibility continuation action must follow allowsSparkDeeper"
        )
        XCTAssertTrue(
            card.contains(
                ".font(.system(size: 17, weight: .regular, design: .rounded))"
            )
        )
        XCTAssertTrue(card.contains(".lineSpacing(5)"))
        XCTAssertTrue(card.contains("iconSize: CGFloat = 22"))
        XCTAssertTrue(
            card.contains("iconSize: 24"),
            "Favorite uses the same optical compensation as the Flow footer"
        )
        XCTAssertTrue(
            card.contains("image: result.card.isLiked ? \"like_active\" : \"like\"")
        )
        XCTAssertTrue(
            card.contains("count: result.card.likeCount"),
            "Spark and Flow cards must expose the same engagement metrics"
        )
        XCTAssertTrue(card.contains(".frame(width: iconSize, height: iconSize)"))
        XCTAssertTrue(card.contains(".frame(minWidth: 44, minHeight: 44)"))
    }

    private func sparkResultCardSource() throws -> String {
        let source = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )
        guard let start = source.range(of: "private struct SparkResultCard: View"),
              let end = source.range(
                of: "private struct SparkGestureIndicator: View"
              ) else {
            XCTFail("Unable to isolate SparkResultCard source")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
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
