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
