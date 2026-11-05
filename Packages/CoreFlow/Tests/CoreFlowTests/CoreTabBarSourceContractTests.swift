import Foundation
import XCTest

final class CoreTabBarSourceContractTests: XCTestCase {
    func testProductRootUsesNativeTabsWithStableDestinations() throws {
        let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/TabBarView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TabView(selection: Binding("))
        for (destination, name, symbol) in [("flow", "Explore", "safari"), ("library", "Home", "square.stack"), ("chat", "Chat", "bubble.left.and.bubble.right")] {
            XCTAssertTrue(source.contains(".tag(CoreTab.\(destination))"))
            XCTAssertTrue(source.contains("Label(\"\(name)\", systemImage: \"\(symbol)\")"))
            XCTAssertTrue(source.contains("\"tab.\(destination)\""))
        }
        XCTAssertFalse(source.contains("PageTabViewStyle"))
        XCTAssertFalse(source.contains("UIScrollView.appearance().isScrollEnabled = false"), "Changing tabs must not globally disable content scrolling")
        XCTAssertTrue(source.contains("for: .tabBar"), "Covered editing surfaces must control native tab visibility")
    }

    func testEmbeddedTabControlPreservesSemanticSelectionAndTapTargets() throws {
        let source = try coreTabBarSource()
        XCTAssertTrue(source.contains(".isSelected"))
        XCTAssertTrue(source.contains("minHeight: 48"))
        XCTAssertTrue(source.contains("ChoraiTheme.ink"))
        XCTAssertTrue(source.contains(".choraiGlassSurface"))
        XCTAssertFalse(source.contains("red: 0.21, green: 0.13, blue: 0.29"))
    }

    func testEachNativeTabOwnsItsNavigationStackAndSidebarRoutes() throws {
        let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/TabBarView.swift"), encoding: .utf8)
        for tab in ["flow", "library", "chat"] {
            XCTAssertTrue(source.contains("tabNavigationRoot(.\(tab))"), "Each tab must own its navigation container so its title and toolbar reach that container")
        }
        XCTAssertTrue(source.contains("NavigationStack(path: navigationPath(for: tab))"))
        XCTAssertTrue(source.contains("@State private var navigationPaths: [CoreTab: NavigationPath]"))
        XCTAssertTrue(source.contains("if coordinator.selectedTab == tab {\n                    SideMenuView("), "Sidebar destinations must be inside the currently selected navigation host")
        XCTAssertFalse(source.contains("NavigationStack(path: $navigationPath)"), "An outer NavigationStack collapses the tab navigation containers")
        XCTAssertFalse(source.contains("CHORAI_NAV"))
    }

    func testAuthenticatedProductDoesNotInheritTheSignInNavigationStack() throws {
        let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/ContentView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Group {\n            if authManager.isAuthenticated || authManager.canOpenLocalNotes {\n                authenticatedView"))
        XCTAssertTrue(source.contains("NavigationStack { loginView }"), "Sign-in keeps its own navigation destinations")
        XCTAssertTrue(source.contains("if authManager.needsInterestSelection && authManager.canEnterProduct {\n                NavigationStack {"))
        XCTAssertTrue(source.contains("ChooseInterestsView(onComplete: authManager.completeInterestSelection)"))
        XCTAssertFalse(source.contains("NavigationStack {\n            if authManager.isAuthenticated"))
    }

    func testPushedReadingWritingProfileAndChatSurfacesHideTheTabBar() throws {
        for path in ["ArcNote/DetailView.swift", "ArcNote/NewNoteView.swift", "ArcNote/UserProfileView.swift", "ArcNote/ChatDetailView.swift", "ArcNote/ChoraProfileView.swift"] {
            let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains(".toolbar(.hidden, for: .tabBar)"), "\(path) must remain a full reading or task surface when pushed inside a tab")
        }
        let popup = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/PopupMenuView.swift"), encoding: .utf8)
        XCTAssertTrue(popup.contains("destination\n            .toolbar(.hidden, for: .tabBar)"), "The shared card router must hide tabs for Spark, Merge, and source destinations too")
    }

    func testColdSidebarLibrarySelectionSurvivesLazyTabMounting() throws {
        let tab = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/TabBarView.swift"), encoding: .utf8)
        let home = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/HomeView.swift"), encoding: .utf8)
        XCTAssertTrue(tab.contains("coordinator.openLibrary(scope: .collect)"))
        XCTAssertTrue(tab.contains("coordinator.openLibrary(scope: .notes)"))
        XCTAssertTrue(tab.contains("librarySelectionRequest: coordinator.librarySelectionRequest"))
        XCTAssertTrue(home.contains(".onChange(of: librarySelectionRequest?.id)"))
        XCTAssertTrue(home.contains("applyLibrarySelectionRequest()"))
        XCTAssertTrue(home.contains("handledLibrarySelectionRequestID != request.id"), "Reappearing Home must not replay an already handled sidebar selection")
    }

    func testThemeSupportsSystemAppearanceAndAccessibilityFallback() throws {
        let theme = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/ChoraiTheme.swift"), encoding: .utf8)
        let project = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertFalse(project.contains("UIUserInterfaceStyle = Light"))
        XCTAssertTrue(theme.contains("traits.userInterfaceStyle == .dark"))
        XCTAssertTrue(theme.contains("accessibilityReduceTransparency"))
        XCTAssertTrue(theme.contains("contrast == .increased"))
        XCTAssertTrue(theme.contains("#available(iOS 26.0, *)"))
        XCTAssertTrue(theme.contains(".glassEffect(.regular"))
        XCTAssertTrue(theme.contains(".background(.regularMaterial"))
    }

    func testHiddenCommentSheetCannotPeekThroughTheTabBarSafeArea() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "ArcNote/CommentPopupView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ChoraiNativeSheetPresenter("))
        XCTAssertTrue(source.contains("isPresented: $manager.isShowing"))
        XCTAssertTrue(source.contains("detents: [.medium(), .large()]"))
        XCTAssertTrue(source.contains(".frame(width: 0, height: 0)"), "The root presenter has no hidden content extending into the tab bar")
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"), "The native sheet owns its composer and keyboard safe area")
        XCTAssertFalse(source.contains("slideOffset"), "Native presentation must not retain the old offscreen sheet")
        XCTAssertFalse(source.contains("GeometryReader"), "Native detents replace manual sheet geometry")
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
