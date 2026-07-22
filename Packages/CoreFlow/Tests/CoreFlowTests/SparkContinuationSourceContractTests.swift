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

    func testSparkScopesWhiteForegroundStyleAwayFromSharedCommentPopup() throws {
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )

        XCTAssertTrue(
            continuation.contains(
                ".padding(.bottom, 18)\n            .foregroundStyle(.white)\n\n            automationAnchors"
            ),
            "Spark's white foreground style must stay scoped to its screen content"
        )
        XCTAssertFalse(
            continuation.contains(
                "}\n        .foregroundStyle(.white)\n        .navigationBarHidden(true)"
            ),
            "A root foreground style leaks into CommentPopupView and changes Explore's material"
        )
        XCTAssertTrue(
            continuation.contains(
                "CommentPopupView()\n                .environment(\\.colorScheme, .light)"
            ),
            "Spark must render the shared comment popup in Explore's app-level Light environment"
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
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )
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
        XCTAssertTrue(
            card.contains(".disabled(!allowsSparkDeeper)"),
            "The direct continuation button must follow the loaded state"
        )
        XCTAssertTrue(
            card.contains(
                ".font(.system(size: 17, weight: .regular, design: .rounded))"
            )
        )
        XCTAssertTrue(card.contains(".lineSpacing(5)"))
        XCTAssertTrue(continuation.contains("iconSize: CGFloat = 22"))
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
        XCTAssertTrue(
            continuation.contains(".frame(width: iconSize, height: iconSize)")
        )
        XCTAssertTrue(
            continuation.contains(".frame(minWidth: 44, minHeight: 44)")
        )
    }

    func testSparkFooterFavoriteIsInteractiveAndOutsideTheDetailTapRegion() throws {
        let card = try sparkResultCardSource()

        XCTAssertTrue(card.contains("let onToggleFavorite: () -> Void"))
        XCTAssertTrue(card.contains("Button(action: onToggleFavorite)"))
        XCTAssertTrue(
            card.contains(
                ".accessibilityIdentifier(\"spark.favorite.\\(result.id)\")"
            )
        )
        XCTAssertTrue(
            card.contains(
                ".accessibilityValue(result.card.isFavorited ? \"true\" : \"false\")"
            )
        )

        guard let contentStart = card.range(of: "private var tappableContent"),
              let footerStart = card.range(of: "private var engagementFooter") else {
            XCTFail("Unable to isolate the Spark content and footer regions")
            return
        }

        let tappableContent = String(
            card[contentStart.lowerBound..<footerStart.lowerBound]
        )
        let engagementFooter = String(card[footerStart.lowerBound...])
        XCTAssertTrue(tappableContent.contains(".onTapGesture(perform: onOpenCard)"))
        XCTAssertFalse(
            engagementFooter.contains(".onTapGesture(perform: onOpenCard)"),
            "The footer must not inherit the card-detail tap target"
        )
    }

    func testSparkFooterLikeAndCommentsAreInteractive() throws {
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )
        let card = try sparkResultCardSource()

        XCTAssertTrue(
            continuation.contains("@StateObject private var likeStore = CardLikeStore(")
        )
        XCTAssertTrue(continuation.contains("store.applyLikeState(state)"))
        XCTAssertTrue(card.contains("let isLikeMutationInFlight: Bool"))
        XCTAssertTrue(card.contains("let onToggleLike: () -> Void"))
        XCTAssertTrue(card.contains("Button(action: onToggleLike)"))
        XCTAssertTrue(card.contains(".disabled(isLikeMutationInFlight)"))
        XCTAssertTrue(
            card.contains(
                ".accessibilityIdentifier(\"spark.like.\\(result.id)\")"
            )
        )
        XCTAssertTrue(card.contains("CommentButton("))
        XCTAssertTrue(card.contains("cardId: result.card.id"))
        XCTAssertTrue(
            card.contains(
                ".accessibilityIdentifier(\"spark.comment.\\(result.id)\")"
            )
        )
    }

    func testKeywordResultsDoNotRenderKeywordBucketLabel() throws {
        let card = try sparkResultCardSource()

        XCTAssertTrue(card.contains("if let bucketLabel"))
        XCTAssertTrue(card.contains("private var bucketLabel: String?"))
        XCTAssertTrue(
            card.contains("case .keywords:\n            return nil")
        )
        XCTAssertFalse(card.contains("return \"KEYWORD\""))
    }

    func testSparkCardHasNoBottomCueUpwardContinuationOrSavedOverlay() throws {
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )
        let card = try sparkResultCardSource()

        XCTAssertFalse(continuation.contains("SparkUpwardCue"))
        XCTAssertFalse(card.contains("SparkDeeperAccessibilityActionModifier"))
        XCTAssertFalse(card.contains("case .sparkDeeper"))
        XCTAssertFalse(card.contains("let onSave: () -> Void"))
        XCTAssertFalse(card.contains("Save result"))
        XCTAssertFalse(continuation.contains("case .saved"))
        XCTAssertFalse(continuation.contains("spark.save.undo"))
        XCTAssertFalse(continuation.contains("SparkIconNotice"))
    }

    private func sparkResultCardSource() throws -> String {
        let source = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )
        guard let start = source.range(of: "private struct SparkResultCard: View"),
              let end = source.range(of: "private struct SparkAvatar: View") else {
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
