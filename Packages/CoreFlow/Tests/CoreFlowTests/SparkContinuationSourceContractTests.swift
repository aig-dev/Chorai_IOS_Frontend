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

    func testSparkUsesAdaptiveInkWithoutForcingCommentPopupAppearance() throws {
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )

        XCTAssertTrue(
            continuation.contains(".foregroundStyle(ChoraiTheme.ink)"),
            "Spark content follows the shared adaptive foreground"
        )
        XCTAssertFalse(continuation.contains("CommentPopupView()"), "Spark uses the app's single scene-aware comment presenter")
        XCTAssertTrue(try source(at: "ArcNote/ArcNoteApp.swift").contains(".overlay { CommentPopupView() }"))
        XCTAssertFalse(continuation.contains(".preferredColorScheme(.dark)"))
        XCTAssertFalse(continuation.contains(".environment(\\.colorScheme, .light)"))
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
            continuation.contains("Label(\"Continue Spark\", systemImage: \"sparkles\")"),
            "Touch users retain a direct continuation action in the approved bottom dock"
        )
        XCTAssertTrue(
            continuation.contains(
                ".accessibilityIdentifier(\"spark.continue.\\(result.id)\")"
            )
        )
        XCTAssertTrue(
            continuation.contains(".disabled(store.phase != .loaded || store.isInteractionLocked)"),
            "The direct continuation button must follow the loaded state"
        )
        XCTAssertTrue(
            card.contains(
                ".font(.system(.title3, design: .serif))"
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
        XCTAssertTrue(
            card.contains("if !result.card.isOwner"),
            "Owned Spark results must not expose a favorite action"
        )
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

        guard let contentStart = card.range(of: "private func tappableContent("),
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

    func testSparkFavoriteCalloutKeepsReadableMobileWidth() throws {
        let card = try sparkResultCardSource()

        XCTAssertTrue(card.contains("tip: .sparkFavorite"))
        XCTAssertTrue(
            card.contains(".frame(width: 220, alignment: .leading)"),
            "The callout is hosted by a 44-point footer button, so it needs an explicit readable width"
        )
    }

    func testSparkFooterLikeAndCommentsAreInteractive() throws {
        let continuation = try source(
            at: "ArcNote/CoreFlow/SparkContinuationViews.swift"
        )
        let card = try sparkResultCardSource()

        XCTAssertTrue(
            continuation.contains("@StateObject private var likeStore: CardLikeStore")
        )
        XCTAssertTrue(
            continuation.contains("service: NetworkCoreCardLikeService()")
        )
        XCTAssertTrue(
            continuation.contains("onCommit: CardEngagementCenter.shared.publish")
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

    func testOfflineFidelityRouteInjectsRealSparkStoresWithoutNetworkNavigation() throws {
        let app = try source(at: "ArcNote/ArcNoteApp.swift")
        let view = try source(at: "ArcNote/CoreFlow/SparkContinuationViews.swift")
        XCTAssertTrue(app.contains("--ui-test-spark-fidelity"))
        XCTAssertTrue(app.contains("SparkContinuationView.fidelityFixture()"))
        XCTAssertTrue(view.contains("static func fidelityFixture() -> SparkContinuationView"))
        XCTAssertTrue(view.contains("service: service,\n            persistence: SparkFidelityMemoryPersistence()"))
        XCTAssertTrue(view.contains("service: SparkFidelityLikeService()"))
        XCTAssertTrue(view.contains("service.applyLikeState(state)"))
        XCTAssertTrue(view.contains("session.applyLikeState(state)"))
        XCTAssertTrue(view.contains("Sample results · no AI request"))
        XCTAssertTrue(view.contains("spark.fixture.offline"))
        XCTAssertFalse(view.contains("CommentPopupView()"), "An existing Spark sheet must not own a second competing comment presenter")
        XCTAssertTrue(view.contains(".disabled(!allowsNetworkNavigation)"))
        for action in ["openDetail(_ cardID: String)", "openAuthor(_ authorID: String)"] {
            XCTAssertTrue(view.contains("private func \(action) {\n        guard allowsNetworkNavigation else {"))
        }
        XCTAssertTrue(view.contains("private func openMenu(_ card: FlowCard) {\n        guard allowsNativeMenuPresentation else {"))
        XCTAssertTrue(view.contains("guard allowsNetworkNavigation else { return }\n                                NotificationCenter.default.post"))
        let fixtureStart = try XCTUnwrap(view.range(of: "#if DEBUG\n// Offline fidelity data"))
        let fixtures = String(view[fixtureStart.lowerBound...])
        XCTAssertFalse(fixtures.contains("NetworkCore"))
        XCTAssertFalse(fixtures.contains("UserDefaults"))
        XCTAssertTrue(fixtures.contains("private final class SparkFidelityService: CoreSparkServing"))
        XCTAssertTrue(fixtures.contains("private actor SparkFidelityLikeService: CoreCardLikeServing"))
        XCTAssertTrue(fixtures.contains("fixture-spark-source"))
        XCTAssertTrue(fixtures.contains("fixture-spark-nia"))
        XCTAssertTrue(fixtures.contains("fixture-spark-leo"))
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
