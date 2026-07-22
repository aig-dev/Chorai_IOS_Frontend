import Foundation
import XCTest

final class CoreTabBarSourceContractTests: XCTestCase {
    func testProductTabsUseTheProvidedInactiveAndActiveAssets() throws {
        let source = try coreTabBarSource()

        let expectedTabs = [
            (".flow", "Explore", "tab_explore", "tab_explore_active", "flow"),
            (".library", "Home", "tab_home", "tab_home_active", "library"),
            (".chat", "Chat", "tab_chat", "tab_chat_active", "chat"),
        ]

        for (tab, label, image, activeImage, identifier) in expectedTabs {
            XCTAssertTrue(source.contains("tab(\(tab),"), "Missing \(tab) tab")
            XCTAssertTrue(source.contains("label: \"\(label)\""), "Missing \(label) copy")
            XCTAssertTrue(source.contains("image: \"\(image)\""), "Missing \(image) asset")
            XCTAssertTrue(
                source.contains("activeImage: \"\(activeImage)\""),
                "Missing \(activeImage) asset"
            )
            XCTAssertTrue(
                source.contains("identifier: \"\(identifier)\""),
                "Missing stable tab.\(identifier) automation identifier"
            )
        }

        XCTAssertFalse(
            source.contains("Image(systemName: image)"),
            "The product tab bar must not replace supplied artwork with SF Symbols"
        )
    }

    func testSelectedTabUsesTheReferenceScaleColorAndTypography() throws {
        let source = try coreTabBarSource()

        XCTAssertTrue(source.contains("selectedIconFrame: CGFloat = 35"))
        XCTAssertTrue(source.contains("unselectedIconFrame: CGFloat = 26"))
        XCTAssertTrue(source.contains("selectedIconScale: CGFloat = 1.1"))
        XCTAssertTrue(source.contains("labelFontSize: CGFloat = 12"))
        XCTAssertTrue(source.contains("selectedTab == tab ? activeImage : image"))
        XCTAssertTrue(source.contains("selectedTab == tab ? .semibold : .medium"))
        XCTAssertTrue(source.contains("selectedTab == tab ? .white : .white.opacity(0.7)"))
        XCTAssertTrue(source.contains("response: 0.5, dampingFraction: 0.7"))
    }

    func testReferenceCapsuleKeepsEqualTabsAndNoRectangularScrim() throws {
        let source = try coreTabBarSource()

        XCTAssertTrue(source.contains("horizontalContentInset: CGFloat = 20"))
        XCTAssertTrue(source.contains(".frame(height: ZenVisualTokens.tabHeight)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        XCTAssertTrue(source.contains("Capsule().fill(.ultraThinMaterial.opacity(0.55))"))
        XCTAssertTrue(source.contains("red: 0.21, green: 0.13, blue: 0.29"))
        XCTAssertTrue(source.contains(".opacity(0.8)"))
        XCTAssertTrue(source.contains("contrast == .increased ? 0.42 : 0.3"))
        XCTAssertFalse(source.contains("verticalContentInset"))
        XCTAssertFalse(
            source.contains("LinearGradient"),
            "The reference bar floats directly over the page without a rectangular scrim"
        )
    }

    func testHiddenCommentSheetCannotPeekThroughTheTabBarSafeArea() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "ArcNote/CommentPopupView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".opacity(manager.isShowing ? 1 : 0)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(manager.isShowing)"))
    }

    private func coreTabBarSource() throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "ArcNote/CoreFlow/CoreShellViews.swift"
            ),
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
