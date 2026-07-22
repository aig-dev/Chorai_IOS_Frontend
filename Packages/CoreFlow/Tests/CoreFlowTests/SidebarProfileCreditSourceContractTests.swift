import Foundation
import XCTest

final class SidebarProfileCreditSourceContractTests: XCTestCase {
    func testSynUsesOnlyOrdinaryCreditsAcrossProfileSurfaces() throws {
        let model = try source(at: "ArcNote/Models/UserProfileModels.swift")
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")
        let profile = try source(at: "ArcNote/MyProfileView.swift")

        let synImplementation = """
    var synBalance: Int {
        creditBalance
            .filter { $0.creditTier == "credit" }
            .reduce(0) { $0 + $1.balance }
    }
"""
        XCTAssertTrue(model.contains(synImplementation))
        XCTAssertTrue(sidebar.contains("userProfileManager.synBalance"))
        XCTAssertTrue(profile.contains("userProfileManager.synBalance"))
        XCTAssertFalse(sidebar.contains("userProfileManager.creditTotal"))
        XCTAssertFalse(profile.contains("userProfileManager.creditTotal"))
    }

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
