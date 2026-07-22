import XCTest
@testable import CoreFlow

final class CommentModelsTests: XCTestCase {
    func testDecodesProfileAudienceAndNeverUsesActorIDAsDisplayName() throws {
        let data = Data(
            #"""
            {
              "comment_id":"cmt_1",
              "comment_asset_id":"ast_comment_1",
              "card_id":"ast_card",
              "actor_id":"act_internal_1",
              "username":"Alice",
              "avatar_url":"/uploads/avatars/alice.png",
              "visibility":"private",
              "body":"Hello",
              "created_at":"2026-07-22T07:06:23.956262Z"
            }
            """#.utf8
        )

        let comment = try JSONDecoder().decode(CommentModel.self, from: data)

        XCTAssertEqual(comment.user.id, "act_internal_1")
        XCTAssertEqual(comment.user.displayName, "Alice")
        XCTAssertEqual(comment.user.avatarUrl, "/uploads/avatars/alice.png")
        XCTAssertEqual(comment.visibility, .privateComment)
        XCTAssertTrue(comment.replies.isEmpty)
    }

    func testMissingOrBlankProfileUsesNeutralDisplayName() throws {
        let missingProfile = CommentUser(id: "act_secret", username: nil, avatarUrl: nil)
        let blankProfile = CommentUser(id: "act_secret", username: "   ", avatarUrl: nil)
        let internalIDProfile = CommentUser(id: "act_secret", username: "act_secret", avatarUrl: nil)

        XCTAssertEqual(missingProfile.displayName, "Chorai user")
        XCTAssertEqual(blankProfile.displayName, "Chorai user")
        XCTAssertEqual(internalIDProfile.displayName, "Chorai user")
        XCTAssertFalse(missingProfile.displayName.contains("act_"))
    }

    func testLegacyCommentDefaultsToPublicAudience() throws {
        let data = Data(
            #"""
            {
              "comment_id":"cmt_legacy",
              "comment_asset_id":"ast_comment_legacy",
              "card_id":"ast_card",
              "actor_id":"act_legacy",
              "body":"Legacy",
              "created_at":"2026-07-22T07:06:23Z"
            }
            """#.utf8
        )

        let comment = try JSONDecoder().decode(CommentModel.self, from: data)

        XCTAssertEqual(comment.visibility, .publicComment)
        XCTAssertEqual(comment.user.displayName, "Chorai user")
    }

    func testAssembleThreadsNestsRepliesAndKeepsOrphansVisible() {
        let user = CommentUser(id: "act_alice", username: "Alice", avatarUrl: nil)
        let root = fixture(id: "root", parentID: nil, user: user)
        let reply = fixture(id: "reply", parentID: "root", user: user)
        let nestedReply = fixture(id: "nested", parentID: "reply", user: user)
        let orphan = fixture(id: "orphan", parentID: "missing", user: user)

        let threads = CommentModel.assembleThreads(from: [root, reply, nestedReply, orphan, reply])

        XCTAssertEqual(threads.map(\.id), ["root", "orphan"])
        XCTAssertEqual(threads[0].replies.map(\.id), ["reply"])
        XCTAssertEqual(threads[0].replies[0].replies.map(\.id), ["nested"])
        XCTAssertTrue(threads[1].replies.isEmpty)
    }

    func testTimestampFormattingAcceptsBackendRFC3339FractionsAndOffsets() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-22T07:08:23Z")
        )

        XCTAssertEqual(
            CommentTimestamp.displayText(
                for: "2026-07-22T07:06:23.956262Z",
                relativeTo: now
            ),
            "1分钟前"
        )
        XCTAssertEqual(
            CommentTimestamp.displayText(
                for: "2026-07-22T15:08:00+08:00",
                relativeTo: now
            ),
            "刚刚"
        )
    }

    private func fixture(
        id: String,
        parentID: String?,
        user: CommentUser
    ) -> CommentModel {
        CommentModel(
            id: id,
            commentAssetId: "ast_\(id)",
            cardId: "ast_card",
            parentCommentId: parentID,
            visibility: .publicComment,
            content: id,
            createdAt: "2026-07-22T07:06:23Z",
            updatedAt: nil,
            user: user,
            replies: []
        )
    }
}
