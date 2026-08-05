import Foundation
import XCTest

final class SidebarProfileCreditSourceContractTests: XCTestCase {
    func testSidebarUsesProfileMediaAndClipsWholeDrawerBeforeOffset() throws {
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")

        XCTAssertTrue(sidebar.contains("private var profileBackground: some View"))
        XCTAssertTrue(sidebar.contains("profileResourceURL("))
        XCTAssertTrue(
            sidebar.contains("userProfileManager.userProfile?.background")
        )
        XCTAssertTrue(
            sidebar.contains("userProfileManager.userProfile?.avatar")
        )
        XCTAssertTrue(sidebar.contains("APIConfiguration.resourceURLString"))
        XCTAssertTrue(sidebar.contains("Image(\"side_bg\")"))
        XCTAssertTrue(sidebar.contains("Image(\"avatar\")"))

        let clipBeforeOffset = """
                .frame(width: adaptiveLayout.drawerWidth)
                .ignoresSafeArea()
                .clipped()
                .offset(x: isPresented ? 0 : -adaptiveLayout.drawerWidth)
"""
        XCTAssertTrue(sidebar.contains(clipBeforeOffset))
    }

    func testSidebarKeepsFollowCountTextIdentityStableWhileProfileLoads() throws {
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")

        XCTAssertFalse(sidebar.contains("if userProfileManager.isLoading"))
        XCTAssertTrue(
            sidebar.contains(
                "Text(userProfileManager.isLoading ? \"--\" : \"\\(userProfileManager.userProfile?.followingCount ?? 0)\")"
            )
        )
        XCTAssertTrue(
            sidebar.contains(
                "Text(userProfileManager.isLoading ? \"--\" : \"\\(userProfileManager.userProfile?.followersCount ?? 0)\")"
            )
        )
    }

    func testSidebarRevealsFollowCountsOnlyAfterDrawerAnimationCompletes() throws {
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")

        XCTAssertTrue(
            sidebar.contains("@State private var areFollowCountsVisible = false")
        )
        XCTAssertEqual(
            sidebar.components(
                separatedBy: ".opacity(areFollowCountsVisible ? 1 : 0)"
            ).count - 1,
            2
        )
        XCTAssertTrue(sidebar.contains(".task(id: isPresented)"))
        XCTAssertTrue(sidebar.contains("try await Task.sleep(nanoseconds: 300_000_000)"))
        XCTAssertTrue(sidebar.contains("guard !Task.isCancelled, isPresented else"))
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
