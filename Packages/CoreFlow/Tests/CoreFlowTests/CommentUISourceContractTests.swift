import Foundation
import XCTest

final class CommentUISourceContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testCommentSheetRestoresPrivateToggleReplyAndSafeProfilePresentation() throws {
        let popup = try source(at: "ArcNote/CommentPopupView.swift")
        let network = try source(at: "ArcNote/NetworkManager.swift")
        let models = try source(at: "ArcNote/Models/CommentModels.swift")

        XCTAssertTrue(popup.contains(#"Image(isPrivateMode ? "secret_active" : "secret")"#))
        XCTAssertTrue(popup.contains(#".accessibilityIdentifier("comment.visibility.toggle")"#))
        XCTAssertTrue(popup.contains(#".accessibilityIdentifier("comment.reply.\(comment.id)")"#))
        XCTAssertTrue(popup.contains("APIConfiguration.resourceURLString"))
        XCTAssertTrue(popup.contains("comment.user.displayName"))
        XCTAssertFalse(popup.contains("comment.user.username ?? comment.user.id"))
        XCTAssertTrue(network.contains(#"parameters["parent_comment_id"]"#))
        XCTAssertTrue(network.contains(#""visibility": request.visibility.rawValue"#))
        XCTAssertTrue(models.contains("CommentModel.assembleThreads"))
        XCTAssertTrue(popup.contains(#".id("comment-load-more-\(manager.loadedCommentCount)")"#))
        XCTAssertTrue(popup.contains("manager.loadMoreComments()"))
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
