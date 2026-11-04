import Foundation
import XCTest
@testable import CoreFlow

final class LocalPreviewTests: XCTestCase {
    func testRequiresEveryDevelopmentBoundary() {
        func enabled(debug: Bool = true, simulator: Bool = true, environment: String = "local", arguments: [String] = ["--dev-preview"], override: String? = nil) -> Bool {
            LocalPreviewPolicy.isEnabled(isDebug: debug, isSimulator: simulator, compiledEnvironment: environment, arguments: arguments, apiOverride: override)
        }
        XCTAssertTrue(enabled())
        XCTAssertFalse(enabled(debug: false))
        XCTAssertFalse(enabled(simulator: false))
        XCTAssertFalse(enabled(environment: "production"))
        XCTAssertFalse(enabled(arguments: []))
        XCTAssertFalse(enabled(override: "diagnostic override"))
        XCTAssertFalse(enabled(override: " "))
    }

    func testUnsupportedReadsAndAllWritesFailClosed() throws {
        for (method, path) in [("POST", "/api/cards"), ("POST", "/api/v1/merge/jobs"), ("GET", "/unknown"), ("DELETE", "/api/cards/preview-note")] {
            let response = LocalPreviewFixtures.response(method: method, path: path)
            XCTAssertEqual(response.statusCode, 503)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
            XCTAssertEqual(body["success"] as? Bool, false)
            XCTAssertTrue((body["message"] as? String)?.contains("Local Preview") == true)
        }
    }

    func testLibraryAndFlowProvideReadableOfflineCards() throws {
        for path in ["/api/cards", "/api/v1/explore/recommended"] {
            let response = LocalPreviewFixtures.response(method: "GET", path: path)
            XCTAssertEqual(response.statusCode, 200)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
            let cards = try XCTUnwrap(body["data"] as? [[String: Any]])
            XCTAssertEqual(cards.count, path == "/api/cards" ? 2 : 6)
            if path == "/api/cards" {
                XCTAssertTrue(cards.allSatisfy { $0["is_owner"] as? Bool == true })
                XCTAssertEqual((body["meta"] as? [String: Any])?["total"] as? Int, 2)
            }
            XCTAssertFalse(try XCTUnwrap(cards.first?["content"] as? String).isEmpty)
            XCTAssertFalse(String(decoding: response.data, as: UTF8.self).contains("https://"))
        }
    }
    func testSampleReaderAuthorHasReadOnlyProfileWithoutBlockingNavigation() throws {
        let path = "/api/v1/profile/preview-author"
        let response = LocalPreviewFixtures.response(method: "GET", path: path)
        XCTAssertEqual(response.statusCode, 200)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let author = try XCTUnwrap(body["data"] as? [String: Any])
        XCTAssertEqual(author["actor_id"] as? String, "preview-author")
        XCTAssertEqual(author["username"] as? String, "Mira Chen")
        XCTAssertEqual(author["is_following"] as? Bool, false)
        XCTAssertEqual(LocalPreviewFixtures.response(method: "POST", path: path).statusCode, 503)
    }

    func testExploreSearchUsesOnlyExistingPublicSamplesAndRejectsWrites() throws {
        let path = "/api/v1/explore/search"
        let response = LocalPreviewFixtures.response(method: "GET", path: path)
        XCTAssertEqual(response.statusCode, 200)
        let cards = try sampleCards(path: path)
        XCTAssertEqual(cards.compactMap { $0["id"] as? String },
            try sampleCards(path: "/api/v1/explore/recommended").compactMap { $0["id"] as? String })
        XCTAssertTrue(cards.allSatisfy { $0["is_public"] as? Bool == true })
        XCTAssertTrue(cards.allSatisfy { ($0["author"] as? [String: Any])?["avatar_url"] is String },
            "The existing SearchAuthor decoder requires the avatar URL string, even when no photo exists")
        XCTAssertEqual(LocalPreviewFixtures.response(method: "POST", path: path).statusCode, 503)
    }

    func testTransportInterceptsUnknownHostsAndWritesWithoutNetworkFallback() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalPreviewURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://unreachable.invalid/api/cards")!)
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("preview-note"))
        request.httpMethod = "POST"
        let (blockedData, blockedResponse) = try await session.data(for: request)
        XCTAssertEqual((blockedResponse as? HTTPURLResponse)?.statusCode, 503)
        XCTAssertTrue(String(decoding: blockedData, as: UTF8.self).contains("local_preview_unavailable"))
    }

    func testOpeningSampleEditorHasHonestEmptyRelatedLinksButWritesRemainBlocked() throws {
        let path = "/api/cards/preview-note/links"
        let response = LocalPreviewFixtures.response(method: "GET", path: path)
        XCTAssertEqual(response.statusCode, 200)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let links = try XCTUnwrap(body["data"] as? [String: Any])
        for key in ["outgoing_links", "incoming_links", "linked_cards"] {
            XCTAssertEqual((links[key] as? [Any])?.count, 0)
        }
        XCTAssertEqual(LocalPreviewFixtures.response(method: "POST", path: path).statusCode, 503)
        XCTAssertEqual(LocalPreviewFixtures.response(method: "PUT", path: "/api/cards/preview-note").statusCode, 503)
    }

    func testApprovedSamplesKeepStableIDsRatesAuthorsAndTags() throws {
        let cards = try sampleCards(path: "/api/v1/explore/recommended")
        XCTAssertEqual(cards.compactMap { $0["id"] as? String }, ["preview-field-note"] + (1...5).map { "preview-field-note-\($0)" })
        XCTAssertEqual(cards.compactMap { $0["rate"] as? Int }, [1, 3, 9, 27, 81, 243])
        XCTAssertEqual(cards.compactMap { ($0["author"] as? [String: Any])?["username"] as? String }, ["Mira Chen", "Leo Park", "Nia Bell", "Alex Rivers", "Sofia Lane", "Rowan Lee"])
        XCTAssertEqual(cards.compactMap { $0["tags"] as? [String] }, [["Culture", "Attention"], ["Design", "Connections"], ["Writing", "Ideas"], ["Attention", "Everyday"], ["Code", "Ideas"], ["Reading", "Sources"]])
        let owned = try sampleCards(path: "/api/cards")
        XCTAssertEqual(owned.compactMap { $0["id"] as? String }, ["preview-note", "preview-note-2"])
        XCTAssertEqual(owned.compactMap { $0["rate"] as? Int }, [1, 1])
        for card in cards {
            let id = try XCTUnwrap((card["author"] as? [String: Any])?["actor_id"] as? String)
            let response = LocalPreviewFixtures.response(method: "GET", path: "/api/v1/profile/\(id)")
            XCTAssertEqual(response.statusCode, 200)
            let profile = try XCTUnwrap((JSONSerialization.jsonObject(with: response.data) as? [String: Any])?["data"] as? [String: Any])
            XCTAssertEqual(profile["username"] as? String, (card["author"] as? [String: Any])?["username"] as? String)
            XCTAssertEqual(LocalPreviewFixtures.response(method: "POST", path: "/api/v1/profile/\(id)").statusCode, 503)
        }
    }

    func testRichSamplesUseRealBlockNoteSchemaAndPreserveTheirContent() throws {
        let cards = try sampleCards(path: "/api/v1/explore/recommended")
        let documents = try cards.map(sampleBlocks)
        XCTAssertEqual(documents[0].first?["type"] as? String, "heading")
        XCTAssertEqual(documents[1].first?["type"] as? String, "heading")
        XCTAssertTrue(documents[2].contains { $0["type"] as? String == "quote" })
        let checklist = documents[3].filter { $0["type"] as? String == "checkListItem" }
        XCTAssertEqual(checklist.count, 4)
        XCTAssertEqual(checklist.compactMap { ($0["props"] as? [String: Any])?["checked"] as? Bool }, [true, true, false, false])
        let code = try XCTUnwrap(documents[4].first { $0["type"] as? String == "codeBlock" })
        XCTAssertEqual((code["props"] as? [String: Any])?["language"] as? String, "swift")
        XCTAssertTrue(documents[5].contains { $0["type"] as? String == "quote" })
        let expected = ["Attention is a kind of generosity.", "A garden is never quite finished.", "An unfinished thought is an invitation to think together.", "Take the quieter street", "struct SmallRitual", "The Margin Notebook"]
        for (index, card) in cards.enumerated() {
            let content = try XCTUnwrap(card["content"] as? String)
            let json = try XCTUnwrap(card["content_json"] as? String)
            XCTAssertTrue(LibraryCardPreviewParser.parse(content: content, contentJSON: json).text.contains(expected[index]))
            XCTAssertFalse(json.contains("https://"))
            let id = try XCTUnwrap(card["id"] as? String)
            let detail = LocalPreviewFixtures.response(method: "GET", path: "/api/cards/\(id)")
            let detailCard = try XCTUnwrap((JSONSerialization.jsonObject(with: detail.data) as? [String: Any])?["data"] as? [String: Any])
            XCTAssertEqual(detailCard["content_json"] as? String, json)
        }
        let owned = try sampleCards(path: "/api/cards")
        for card in owned { XCTAssertTrue(try sampleBlocks(card).allSatisfy { $0["type"] as? String == "paragraph" }) }
    }

    func testOwnedSamplesAlreadyContainTheEditorsCanonicalParagraphDefaults() throws {
        let defaults = ["backgroundColor": "default", "textColor": "default", "textAlignment": "left"]
        for card in try sampleCards(path: "/api/cards") {
            let blocks = try sampleBlocks(card)
            var hydratedBlocks: [[String: Any]] = []
            for block in blocks {
                XCTAssertEqual(block["type"] as? String, "paragraph")
                XCTAssertEqual(block["props"] as? [String: String], defaults)
                XCTAssertNotNil(block["id"] as? String)
                XCTAssertEqual((block["children"] as? [Any])?.count, 0)
                var hydrated = block
                // The bundled editor materializes these schema defaults on load.
                hydrated["props"] = defaults
                hydratedBlocks.append(hydrated)
            }
            let original = CardEditingDraft(
                title: nil, content: try XCTUnwrap(card["content"] as? String),
                contentJSON: try XCTUnwrap(card["content_json"] as? String),
                tags: try XCTUnwrap(card["tags"] as? [String]), isPublic: false
            )
            let normalizedJSON = String(decoding: try JSONSerialization.data(withJSONObject: hydratedBlocks), as: UTF8.self)
            let opened = CardEditingDraft(
                title: nil, content: "The editor supplies its Markdown projection",
                contentJSON: normalizedJSON, tags: original.tags, isPublic: original.isPublic
            )
            XCTAssertTrue(original.isCommitEquivalent(to: opened), "Opening an unchanged offline note must not require a blocked write")
        }
    }

    func testPhotoReferenceIsHonestTextOnlyWithoutExternalImageRequest() throws {
        let first = try XCTUnwrap(sampleCards(path: "/api/v1/explore/recommended").first)
        let content = try XCTUnwrap(first["content"] as? String)
        let json = try XCTUnwrap(first["content_json"] as? String)
        let preview = LibraryCardPreviewParser.parse(content: content, contentJSON: json)
        XCTAssertNil(preview.imageSource)
        XCTAssertTrue(preview.text.contains("The things we notice become the things we care about."))
    }

    func testReaderHTMLIncludesTheSameQuoteChecklistAndCodeAsStructuredDocument() throws {
        let cards = try sampleCards(path: "/api/v1/explore/recommended")
        let quote = try XCTUnwrap(cards[2]["content"] as? String)
        XCTAssertTrue(quote.contains("<blockquote>An unfinished thought is an invitation to think together.</blockquote>"))
        let checklist = try XCTUnwrap(cards[3]["content"] as? String)
        XCTAssertTrue(checklist.contains("Take the quieter street"))
        XCTAssertTrue(checklist.contains("checked disabled"))
        let code = try XCTUnwrap(cards[4]["content"] as? String)
        XCTAssertTrue(code.contains("<pre><code"))
        XCTAssertTrue(code.contains("struct SmallRitual"))
        let reference = try XCTUnwrap(cards[5]["content"] as? String)
        XCTAssertTrue(reference.contains("The Margin Notebook"))
        XCTAssertTrue(reference.contains("Issue 03 · p. 12"))
    }

    func testPublicAuthorCardsOnlyReturnThatExistingAuthorsPublicContent() throws {
        let explore = try sampleCards(path: "/api/v1/explore/recommended")
        for card in explore {
            let actorID = try XCTUnwrap(card["owner_actor_id"] as? String)
            let response = try responseBody("/api/v1/profile/\(actorID)/cards")
            let cards = try XCTUnwrap(response["data"] as? [[String: Any]])
            XCTAssertEqual(cards.count, 1)
            XCTAssertEqual(cards.first?["id"] as? String, card["id"] as? String)
            XCTAssertTrue(cards.allSatisfy { $0["owner_actor_id"] as? String == actorID && $0["is_public"] as? Bool == true && $0["is_owner"] as? Bool == false })
            XCTAssertEqual((response["meta"] as? [String: Any])?["total"] as? Int, cards.count)
        }
    }

    func testKnownActorsFollowListsUseTheActualCursorEnvelopeAndMatchingProfileCounts() throws {
        let knownIDs = Set([LocalPreviewFixtures.actorID, "preview-author"] + (1...5).map { "preview-author-\($0)" })
        for actorID in knownIDs {
            let profile = try XCTUnwrap(responseBody("/api/v1/profile/\(actorID)")["data"] as? [String: Any])
            for kind in ["followers", "following"] {
                let body = try responseBody("/api/v1/actors/\(actorID)/\(kind)")
                let data = try XCTUnwrap(body["data"] as? [String: Any])
                let items = try XCTUnwrap(data["items"] as? [[String: Any]])
                XCTAssertFalse(items.isEmpty)
                XCTAssertEqual(data["next_cursor"] as? String, "")
                XCTAssertEqual(data["has_more"] as? Bool, false)
                XCTAssertEqual(profile[kind == "followers" ? "follower_count" : "following_count"] as? Int, items.count)
                for item in items {
                    let id = try XCTUnwrap(item["actor_id"] as? String)
                    XCTAssertTrue(knownIDs.contains(id))
                    XCTAssertNotEqual(id, actorID)
                    XCTAssertNotNil(item["username"] as? String)
                    XCTAssertNotNil(item["is_following"] as? Bool)
                    XCTAssertNil(item["avatar_url"], "Offline rows must not request remote images")
                }
            }
        }
    }

    func testPrivacyHasExactlyTheSixExistingBooleanFieldsAndRejectsChanges() throws {
        let path = "/api/v1/profile/me/privacy"
        let data = try XCTUnwrap(responseBody(path)["data"] as? [String: Any])
        XCTAssertEqual(Set(data.keys), Set(PrivacySetting.allCases.map(\.rawValue)))
        for setting in PrivacySetting.allCases { XCTAssertNotNil(data[setting.rawValue] as? Bool) }
        XCTAssertEqual(data["show_email"] as? Bool, false)
        XCTAssertEqual(data["show_phone"] as? Bool, false)
        XCTAssertEqual(data["allow_follow"] as? Bool, true)
        XCTAssertEqual(data["show_follow_lists"] as? Bool, true)
        XCTAssertEqual(LocalPreviewFixtures.response(method: "PUT", path: path).statusCode, 503)
    }

    func testBlockedActorsHaveExistingIdentitiesAndRequiredTimestamp() throws {
        let data = try XCTUnwrap(responseBody("/api/user-blocks")["data"] as? [String: Any])
        let items = try XCTUnwrap(data["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(data["next_cursor"] as? String, "")
        XCTAssertEqual(data["has_more"] as? Bool, false)
        let blocked = try XCTUnwrap(items.first)
        let id = try XCTUnwrap(blocked["actor_id"] as? String)
        let profile = try XCTUnwrap(responseBody("/api/v1/profile/\(id)")["data"] as? [String: Any])
        XCTAssertEqual(blocked["username"] as? String, profile["username"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(blocked["blocked_at"] as? String)))
        XCTAssertEqual(LocalPreviewFixtures.response(method: "DELETE", path: "/api/user-blocks/\(id)").statusCode, 503)
    }

    func testTrashHasReadableOwnedSamplesAndRequiredRetentionFieldsWithoutLiveDuplicates() throws {
        let body = try responseBody("/api/cards/trash")
        let trash = try XCTUnwrap(body["data"] as? [[String: Any]])
        XCTAssertEqual(trash.count, 2)
        let liveIDs = Set(try sampleCards(path: "/api/cards").compactMap { $0["id"] as? String })
        for card in trash {
            let id = try XCTUnwrap(card["id"] as? String)
            XCTAssertFalse(liveIDs.contains(id))
            XCTAssertFalse(try XCTUnwrap(card["content"] as? String).isEmpty)
            XCTAssertNotNil(card["content_hash"] as? String)
            XCTAssertEqual(card["is_public"] as? Bool, false)
            XCTAssertEqual(card["owner_actor_id"] as? String, LocalPreviewFixtures.actorID)
            XCTAssertNotNil(card["tags"] as? [String])
            XCTAssertNotNil(card["like_count"] as? Int)
            XCTAssertNotNil(card["is_liked"] as? Bool)
            for key in ["created_at", "updated_at", "deleted_at"] {
                XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(card[key] as? String)))
            }
            XCTAssertTrue((1...30).contains(try XCTUnwrap(card["days_remaining"] as? Int)))
            let formatter = ISO8601DateFormatter()
            let created = try XCTUnwrap(formatter.date(from: try XCTUnwrap(card["created_at"] as? String)))
            let updated = try XCTUnwrap(formatter.date(from: try XCTUnwrap(card["updated_at"] as? String)))
            let deleted = try XCTUnwrap(formatter.date(from: try XCTUnwrap(card["deleted_at"] as? String)))
            XCTAssertLessThanOrEqual(created, updated)
            XCTAssertLessThanOrEqual(updated, deleted)
            XCTAssertEqual(LocalPreviewFixtures.response(method: "POST", path: "/api/cards/\(id)/restore").statusCode, 503)
            XCTAssertEqual(LocalPreviewFixtures.response(method: "DELETE", path: "/api/cards/\(id)/permanent").statusCode, 503)
        }
        let meta = try XCTUnwrap(body["meta"] as? [String: Any])
        XCTAssertEqual(meta["total"] as? Int, trash.count)
        XCTAssertEqual(meta["page"] as? Int, 1)
        XCTAssertEqual(meta["per_page"] as? Int, 20)
    }

    func testNewPreviewReadsNeverAcceptUnknownActorsOrWrites() throws {
        for path in ["/api/v1/profile/stranger/cards", "/api/v1/actors/stranger/followers", "/api/v1/actors/stranger/following", "/api/v1/profile/stranger/privacy", "/api/user-blocks/stranger"] {
            XCTAssertEqual(LocalPreviewFixtures.response(method: "GET", path: path).statusCode, 503)
        }
        for path in ["/api/v1/profile/preview-author/cards", "/api/v1/actors/preview-author/followers", "/api/v1/actors/\(LocalPreviewFixtures.actorID)/following", "/api/v1/profile/me/privacy", "/api/user-blocks", "/api/cards/trash"] {
            for method in ["POST", "PUT", "PATCH", "DELETE"] {
                let response = LocalPreviewFixtures.response(method: method, path: path)
                XCTAssertEqual(response.statusCode, 503)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
                XCTAssertEqual(body["success"] as? Bool, false)
            }
        }
    }

    private func responseBody(_ path: String) throws -> [String: Any] {
        let response = LocalPreviewFixtures.response(method: "GET", path: path)
        XCTAssertEqual(response.statusCode, 200, "Missing offline GET: \(path)")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        XCTAssertEqual(body["success"] as? Bool, true)
        return body
    }

    private func sampleCards(path: String) throws -> [[String: Any]] {
        let response = LocalPreviewFixtures.response(method: "GET", path: path)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        return try XCTUnwrap(body["data"] as? [[String: Any]])
    }

    private func sampleBlocks(_ card: [String: Any]) throws -> [[String: Any]] {
        let json = try XCTUnwrap(card["content_json"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

}
