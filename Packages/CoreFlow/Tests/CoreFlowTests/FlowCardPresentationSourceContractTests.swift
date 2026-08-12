import Foundation
import XCTest

final class FlowCardPresentationSourceContractTests: XCTestCase {
    func testExploreFlowCardUsesBodyWithoutRenderingLegacyTitle() throws {
        let source = try flowCardSource()

        XCTAssertTrue(source.contains("Text(FlowTextPreview.make(card.content))"))
        XCTAssertFalse(
            source.contains("card.title"),
            "Explore cards are titleless even when the API returns a legacy title"
        )
    }

    func testExploreFlowCardUsesUndimmedOpticallyBalancedEngagementIcons() throws {
        let source = try flowCardSource()

        XCTAssertFalse(
            source.contains("imageOpacity"),
            "Favorite must not be dimmer than like and comment"
        )
        XCTAssertTrue(
            source.contains(
                "CommentButton(cardId: card.id, commentCount: card.commentCount, iconSize: 22)"
            ),
            "Comment must use the same 22-point base size as like"
        )
        XCTAssertTrue(
            source.contains("iconSize: CGFloat = 22"),
            "Engagement icons must share a 22-point base size"
        )
        XCTAssertTrue(
            source.contains("iconSize: 24"),
            "Favorite needs optical compensation for its larger transparent canvas"
        )
        XCTAssertTrue(
            source.contains(".frame(width: iconSize, height: iconSize)"),
            "The engagement metric must apply its optical icon size"
        )
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
            source.contains(".frame(width: 32, height: 32)"),
            "The approved Flow avatar is a stable 32-point circle"
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

    func testFlowUsesTintedNativeGlassWithAccessibilityFallbacks() throws {
        let source = try flowViewSource()

        XCTAssertTrue(source.contains("private struct FlowGlassSurface: View"))
        XCTAssertTrue(source.contains("shape.fill(.ultraThinMaterial)"))
        XCTAssertTrue(source.contains("if !reduceTransparency"))
        XCTAssertTrue(source.contains("ZenVisualTokens.opaqueCardFill"))
        XCTAssertTrue(source.contains("FlowGlassSurface(layer: .foreground)"))
        XCTAssertTrue(source.contains("contrast == .increased"))
    }

    func testFlowDeckUsesAtMostTwoTruthfulNoninteractiveBackplates() throws {
        let source = try flowViewSource()

        XCTAssertTrue(source.contains("min(2, max(0, store.cards.count - 1))"))
        XCTAssertTrue(source.contains("ForEach(backplateDepths.reversed(), id: \\.self)"))
        XCTAssertTrue(source.contains("FlowDeckBackplate(depth: depth)"))
        XCTAssertTrue(source.contains(".scaleEffect(depth == 1 ? 0.972 : 0.944)"))
        XCTAssertTrue(source.contains(".offset(x: depth == 1 ? 7 : 14, y: depth == 1 ? 14 : 28)"))
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
