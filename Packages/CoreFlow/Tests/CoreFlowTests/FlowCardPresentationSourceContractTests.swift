import Foundation
import XCTest

final class FlowCardPresentationSourceContractTests: XCTestCase {
    func testExploreMenusKeepTheOriginalMutationBoundary() throws {
        let flow = try flowViewSource()
        let explore = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/ExploreView.swift"), encoding: .utf8)
        XCTAssertFalse(flow.contains("layout: card.isOwner ? .grid3x3"), "Explore cannot offer Home-owned delete, pin, or visibility notifications without a card-specific mutation owner")
        XCTAssertFalse(explore.contains("layout: isCurrentExploreCardOwned ? .grid3x3"), "Search's legacy menu must preserve the same boundary")
        XCTAssertTrue(flow.contains("layout: .grid2x2"))
    }

    func testExploreFlowCardUsesBodyWithoutRenderingLegacyTitle() throws {
        let source = try flowCardSource()

        XCTAssertTrue(source.contains("FlowRichPreview("))
        let views = try flowViewSource()
        XCTAssertTrue(views.contains("RenderedFlowRichPreview(presentation: presentation, compact: compact, cardID: card.id)"))
        XCTAssertFalse(views.contains("JSONSerialization"))
        XCTAssertFalse(views.contains("LibraryCardPreviewParser.parse"))
        XCTAssertFalse(
            source.contains("card.title"),
            "Explore cards are titleless even when the API returns a legacy title"
        )
    }

    func testExploreFlowCardUsesApprovedCompactNativeEngagementIcons() throws {
        let source = try flowCardSource()

        XCTAssertFalse(
            source.contains("imageOpacity"),
            "Favorite must not be dimmer than like and comment"
        )
        XCTAssertTrue(
            source.contains(
                "CommentButton(cardId: card.id, commentCount: card.commentCount, iconSize: 14, countFont: .caption)"
            ),
            "Comment must match the approved 14-point native like icon"
        )
        XCTAssertTrue(
            source.contains("iconSize: CGFloat = 14"),
            "Engagement icons must share the prototype’s 14-point base size"
        )
        XCTAssertTrue(
            source.contains(".frame(minWidth: 44, minHeight: 44)"),
            "Compact native icons must retain a 44-point hit target"
        )
        XCTAssertTrue(
            source.contains(".frame(width: iconSize, height: iconSize)"),
            "The engagement metric must apply its optical icon size"
        )
    }

    func testDeckRendersTheActiveLikeProjection() throws {
        let source = try flowViewSource()
        XCTAssertTrue(source.contains("card.replacingLike(with: likeStore.state)"),
                      "Flow's icon and count must read the local tap projection before the global receipt")
    }

    func testFlowSwipesAndVoiceOverUseOnlyTheBrowseAction() throws {
        let card = try flowCardSource()
        let swipe = try XCTUnwrap(card.components(separatedBy: "private func resolveSwipe(").last)
        XCTAssertTrue(swipe.contains("onDismiss()"))
        XCTAssertFalse(swipe.contains("onCollectAndAdvance"))
        XCTAssertFalse(swipe.contains("onToggleLike"))
        XCTAssertFalse(swipe.contains("onToggleFavorite"))
        XCTAssertTrue(card.contains(#".accessibilityAction(named: Text("Next note"), onDismiss)"#))
        XCTAssertFalse(card.contains("Collect and continue"))
    }

    func testDeckFavoriteWritesOnlyPresentTheirInlineErrorAndScopeGlobalReceipts() throws {
        let flow = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/CoreFlow/NetworkCoreFlowService.swift"), encoding: .utf8)
        let like = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/CoreFlow/NetworkCoreCardLikeService.swift"), encoding: .utf8)
        XCTAssertTrue(flow.contains("favoriteCard(cardId: assetID, presentsError: false)"))
        XCTAssertTrue(flow.contains("unfavoriteCard(cardId: assetID, presentsError: false)"))
        for adapter in [flow, like] {
            XCTAssertTrue(adapter.contains("private let scope: NoteStoreScope?"))
            XCTAssertTrue(adapter.contains("AuthManager.shared.currentNoteScope == scope"))
            XCTAssertTrue(adapter.contains("let session = AuthManager.shared.sessionGeneration"),
                          "The write uses the current session after same-account reauthentication")
            XCTAssertTrue(adapter.contains("AuthManager.shared.sessionGeneration == session"))
        }
    }

    func testOwnedFlowCardOmitsFavoriteControl() throws {
        let source = try flowCardSource()

        XCTAssertTrue(
            source.contains("if !card.isOwner"),
            "Owned cards must not expose a favorite action in Flow"
        )
        XCTAssertTrue(source.contains("onToggleFavorite()"))
    }

    func testFlowAvatarCanonicalizesRelativeResourceURLBeforeLoading() throws {
        let source = try flowCardSource()
        let authorButtonSource = try flowAuthorButtonSource()

        XCTAssertTrue(
            source.contains("APIConfiguration.resourceURLString(rawURL)"),
            "Flow must resolve backend-relative avatar paths against the active API environment"
        )
        XCTAssertTrue(
            source.contains("AsyncImage(url: resolvedAvatarURL)"),
            "AsyncImage must receive the canonical URL"
        )
        XCTAssertTrue(
            source.contains(".frame(width: 34, height: 34)"),
            "The approved Flow avatar is a stable 34-point circle"
        )
        XCTAssertTrue(
            authorButtonSource.contains(".frame(minHeight: 44)"),
            "The author action must keep a 44-point minimum tap target"
        )
        XCTAssertTrue(
            authorButtonSource.contains(".contentShape(Rectangle())"),
            "The author action must make its padded target hittable"
        )
        XCTAssertTrue(
            source.contains("case .failure:"),
            "A failed request must retain the quiet avatar fallback"
        )
    }

    func testFlowUsesReadableNativeSurfaceWithAccessibilityFallbacks() throws {
        let source = try flowViewSource()

        XCTAssertTrue(source.contains("private struct FlowGlassSurface: View"))
        XCTAssertTrue(source.contains("shape.fill(ZenVisualTokens.opaqueCardFill)"))
        XCTAssertTrue(source.contains("guard !reduceTransparency, case .foreground = layer else { return 0 }"))
        XCTAssertTrue(source.contains("scheme == .dark ? 0.1 : 0.025"))
        XCTAssertTrue(source.contains("radius: 16, y: 6"))
        XCTAssertTrue(source.contains("ZenVisualTokens.opaqueCardFill"))
        XCTAssertTrue(source.contains("FlowGlassSurface(layer: .foreground)"))
        XCTAssertTrue(source.contains("contrast == .increased"))
    }

    func testFlowDeckUsesAtMostTwoTruthfulNoninteractiveBackplates() throws {
        let source = try flowViewSource()

        XCTAssertTrue(source.contains("min(2, max(0, store.remainingCount - 1))"))
        XCTAssertTrue(source.contains("ForEach(backplateDepths.reversed(), id: \\.self)"))
        XCTAssertTrue(source.contains("FlowDeckBackplate(depth: depth)"))
        XCTAssertTrue(source.contains(".padding(.horizontal, depth == 1 ? 6 : 12)"))
        XCTAssertTrue(source.contains(".offset(y: depth == 1 ? 6 : 12)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
    }

    func testFlowGlassUIFixtureReusesExistingAvatarArtifact() throws {
        let source = try flowGlassUITestSource()
        let helperSource = try reusableAvatarHelperSource()

        XCTAssertTrue(
            source.contains("reusableRelativeAvatarURL"),
            "The Flow fixture must reuse an existing avatar resource"
        )
        XCTAssertFalse(
            source.contains("avatar-smoke-upload"),
            "The Flow fixture must not create an orphaned upload or consume the avatar upload limit"
        )
        XCTAssertFalse(
            source.contains("waitForEditProfileAvatarUploadStatus"),
            "The Flow fixture must not depend on an upload mutation"
        )
        XCTAssertFalse(
            source.contains("updateCurrentSmokeProfile"),
            "The Flow fixture must require a pre-provisioned relative avatar instead of attempting an unsupported profile avatar write"
        )
        XCTAssertTrue(
            helperSource.contains("candidate.count > 1"),
            "The reusable avatar prerequisite must reject the root path"
        )
    }

    func testGridAndDeckShareLiveStoreAndHideDecorativeChora() throws {
        let source = try flowViewSource()
        XCTAssertTrue(source.contains("let cards = store.browsingCards"))
        XCTAssertTrue(source.contains(".accessibilitySortPriority(Double(cards.count - index))"))
        XCTAssertTrue(source.contains("store.toggleFavorite(assetID: card.id"))
        XCTAssertTrue(source.contains(".choraiCardLevel(rate: card.rate, showsChora: false, cornerRadius: 28)"))
        XCTAssertTrue(source.contains(".choraiCardLevel(rate: card.rate, showsChora: false, cornerRadius: 17)"))
        XCTAssertTrue(source.contains("FlowMasonryLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, spacing: 12, typeSize: typeSize)"))
        XCTAssertTrue(source.contains(".onReceive(CardEngagementCenter.shared.favorites)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(isGrid)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(!isGrid)"))
    }

    func testRatedGridKeepsBoundedSummaryAuthorAndActionsInsideV8LevelSurface() throws {
        let source = try flowViewSource()
        let start = try XCTUnwrap(source.range(of: "private func ratedTile(_ card: FlowCard, excerpt: FlowGridExcerpt?)"))
        let end = try XCTUnwrap(source.range(of: "private struct FlowGridExcerpt", range: start.upperBound..<source.endIndex))
        let tile = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(tile.contains(".font(.system(.subheadline, design: .serif))"))
        XCTAssertTrue(tile.contains(".lineSpacing(3).lineLimit(7)"))
        XCTAssertTrue(tile.contains("minHeight: 126"))
        XCTAssertTrue(tile.contains("VStack(alignment: .leading, spacing: 12)"))
        XCTAssertTrue(tile.contains(".padding(14)"))
        XCTAssertFalse(tile.contains("FlowRichPreview"), "Rated Grid limits the whole summary rather than each rich block separately")
        let surface = try XCTUnwrap(tile.range(of: ".choraiCardLevel(rate: card.rate, showsChora: false, cornerRadius: 17)"))
        for control in ["Open author", "explore.grid.favorite.", "explore.grid.menu."] {
            let position = try XCTUnwrap(tile.range(of: control))
            XCTAssertLessThan(position.lowerBound, surface.lowerBound, "Author and both actions must be inside the shared level border")
        }
    }

    private func flowCardSource() throws -> String {
        let source = try flowViewSource()
        guard let start = source.range(of: "struct FlowCardView: View"),
              let end = source.range(of: "struct FlowDeckView: View") else {
            XCTFail("Unable to isolate FlowCardView source")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func flowAuthorButtonSource() throws -> String {
        let source = try flowCardSource()
        guard let start = source.range(
            of: "Button {\n                    dismissVisibleTips()\n                    onOpenAuthor()"
        ),
              let end = source.range(
                of: "Spacer()",
                range: start.upperBound..<source.endIndex
              ) else {
            XCTFail("Unable to isolate the Flow author button")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func flowViewSource() throws -> String {
        try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("ArcNote/CoreFlow/FlowViews.swift"),
            encoding: .utf8
        )
    }

    private func flowGlassUITestSource() throws -> String {
        let source = try flowUITestFileSource()
        guard let start = source.range(of: "func testFlowGlassDeckRenders"),
              let end = source.range(
                of: "func testFlowFavoriteIconActivatesWithoutAdvancingCard",
                range: start.upperBound..<source.endIndex
              ) else {
            XCTFail("Unable to isolate the Flow glass UI fixture")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func reusableAvatarHelperSource() throws -> String {
        let source = try flowUITestFileSource()
        guard let start = source.range(of: "private func reusableRelativeAvatarURL"),
              let end = source.range(
                of: "private func waitForCurrentSmokeProfile",
                range: start.upperBound..<source.endIndex
              ) else {
            XCTFail("Unable to isolate the reusable avatar helper")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func flowUITestFileSource() throws -> String {
        try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("ArcNoteUITests/ArcNoteUITests.swift"),
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
