import Foundation
import XCTest
@testable import CoreFlow

final class CardResponseModelsTests: XCTestCase {
    func testCardResponseDecodesCurrentCardDTOForMergePresentation() throws {
        let response = try JSONDecoder().decode(
            CardResponseEnvelope.self,
            from: Data(Self.rateFiveCardJSON.utf8)
        )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data.id, "ast_rate_5")
        XCTAssertEqual(response.data.noteDocumentVersionID, "ver_rate_5")
        XCTAssertEqual(response.data.contentJSON, #"{"type":"doc"}"#)
        XCTAssertEqual(
            response.data.backgroundMediaRef,
            "/chorai-assets/rate-5.png"
        )
        XCTAssertEqual(response.data.favoriteCount, 12)
        XCTAssertEqual(response.data.rate, 5)
        XCTAssertEqual(response.data.author?.id, "act_author")
        XCTAssertEqual(response.data.author?.username, "Mira")
        XCTAssertEqual(response.data.author?.avatar, "/avatars/mira.png")
    }

    private static let rateFiveCardJSON = #"""
    {
      "success": true,
      "message": "Card retrieved",
      "data": {
        "id": "ast_rate_5",
        "note_document_version_id": "ver_rate_5",
        "owner_actor_id": "act_author",
        "title": "",
        "content": "A canonical card",
        "content_json": "{\"type\":\"doc\"}",
        "background_media_ref": "/chorai-assets/rate-5.png",
        "editor_atmosphere": "none",
        "content_hash": "sha256:rate-five",
        "tags": ["Design", "Systems"],
        "is_public": true,
        "created_at": "2026-08-13T01:02:03Z",
        "updated_at": "2026-08-13T02:03:04Z",
        "favorite_count": 12,
        "view_count": 34,
        "like_count": 8,
        "comment_count": 3,
        "rate": 5,
        "credit_score": 21,
        "is_owner": false,
        "is_favorited": true,
        "is_pinned": false,
        "is_liked": true,
        "pinned_at": null,
        "pinned_by_actor_id": null,
        "author": {
          "author_id": "act_author",
          "author_name": "Mira",
          "avatar_url": "/avatars/mira.png"
        },
        "is_following_author": true,
        "credit_evaluation": null
      }
    }
    """#
}
