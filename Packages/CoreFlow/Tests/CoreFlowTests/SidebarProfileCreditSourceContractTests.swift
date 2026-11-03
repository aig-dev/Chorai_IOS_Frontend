import Foundation
import XCTest

final class SidebarProfileCreditSourceContractTests: XCTestCase {
    func testCompactSidebarKeepsActualAvatarAndReadableControls() throws {
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")
        XCTAssertTrue(sidebar.contains("userProfileManager.userProfile?.avatar"))
        XCTAssertTrue(sidebar.contains("APIConfiguration.resourceURLString"))
        XCTAssertTrue(sidebar.contains("Image(\"avatar\")"))
        XCTAssertFalse(sidebar.contains("profileBackgroundHeight"), "A decorative banner must not displace profile and menu actions")
        XCTAssertTrue(sidebar.contains("side-menu.close"))
        XCTAssertTrue(sidebar.contains("accessibilityReduceTransparency"))
    }

    func testCachedProfileValuesRemainReadableDuringRefresh() throws {
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")
        XCTAssertFalse(sidebar.contains("userProfileManager.isLoading ?"), "Refresh must not replace cached follow counts with placeholders")
        XCTAssertFalse(sidebar.contains("userProfileManager.isCreditLoading ?"), "Refresh must not replace cached credit with a placeholder")
        XCTAssertTrue(sidebar.contains("userProfileManager.creditBalance.map"))
        XCTAssertTrue(sidebar.contains("userProfileManager.userProfile.map"))
        XCTAssertFalse(sidebar.contains("areFollowCountsVisible"))
        XCTAssertFalse(sidebar.contains("Task.sleep"))
    }

    func testSidebarPresentationKeepsRoutesInTheirOriginalNavigationHost() throws {
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")
        XCTAssertTrue(sidebar.contains("SidebarOverlayPresenter("))
        XCTAssertTrue(sidebar.contains("isPresented && !hasActiveDestination"))
        XCTAssertTrue(sidebar.contains(".navigationDestination(isPresented: $navigateToSettings)"))
        XCTAssertTrue(sidebar.contains(".navigationDestination(isPresented: $navigateToMyProfile)"))
        XCTAssertTrue(sidebar.contains("accessibilityViewIsModal = true"))
        XCTAssertFalse(sidebar.contains("makeKeyAndVisible"), "The drawer must not steal the scene's key window or keyboard")
        XCTAssertFalse(sidebar.contains("asyncAfter"), "Library selection must follow presentation completion, not a guessed delay")
    }

    func testOpeningSidebarDoesNotChangeRootBarVisibility() throws {
        let tabs = try source(at: "ArcNote/TabBarView.swift")
        XCTAssertTrue(tabs.contains(".toolbar(isTabBarCovered || keyboardLayout.isVisible"))
        XCTAssertTrue(tabs.contains("isTabBarCovered || showSideMenu"), "Onboarding must still regard the library as covered")
        for path in ["ArcNote/HomeView.swift", "ArcNote/ExploreView.swift"] {
            let root = try source(at: path)
            XCTAssertFalse(root.contains(".toolbar(showSideMenu ?"), "Opening a drawer must not expand the root viewport")
        }
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
