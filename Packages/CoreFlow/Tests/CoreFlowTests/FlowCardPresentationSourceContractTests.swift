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

    private func flowCardSource() throws -> String {
        let source = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("ArcNote/CoreFlow/FlowViews.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "struct FlowCardView: View"),
              let end = source.range(of: "struct FlowDeckView: View") else {
            XCTFail("Unable to isolate FlowCardView source")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
