import Foundation
import XCTest

final class MyProfileActionsSourceContractTests: XCTestCase {
    func testMyProfileUsesHomeOwnerActionsWithoutCredits() throws {
        let profile = try source(at: "ArcNote/MyProfileView.swift")
        let popupMenu = try source(at: "ArcNote/PopupMenuView.swift")

        XCTAssertFalse(profile.contains("my-profile.credit-balance"))
        XCTAssertFalse(profile.contains("Text(\"Credits\")"))
        XCTAssertTrue(profile.contains("popupMenuLayout = .grid3x3"))
        XCTAssertTrue(profile.contains("onDelete: { requestCardDeletion() }"))
        XCTAssertTrue(
            profile.contains("onToggleVisibility: toggleCardVisibility")
        )
        XCTAssertTrue(profile.contains("onTogglePin: { toggleCardPin($0) }"))

        XCTAssertTrue(popupMenu.contains("onDelete: (@MainActor @Sendable () -> Void)?"))
        XCTAssertTrue(
            popupMenu.contains("onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)?")
        )
        XCTAssertTrue(popupMenu.contains("onTogglePin: (@MainActor @Sendable (UserCard) -> Void)?"))
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
