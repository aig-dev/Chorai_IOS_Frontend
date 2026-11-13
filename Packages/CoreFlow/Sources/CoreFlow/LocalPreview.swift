import Foundation

/// Explicit development-only activation. Callers supply compile-time platform flags.
public enum LocalPreviewPolicy {
    public static func isEnabled(
        isDebug: Bool, isSimulator: Bool, compiledEnvironment: String?,
        arguments: [String], apiOverride: String?
    ) -> Bool {
        isDebug && isSimulator && compiledEnvironment == "local"
            && arguments.contains("--dev-preview") && apiOverride == nil
    }
}

/// Read-only, deterministic content for exploring the real native navigation.
/// No response performs networking or claims a service operation succeeded.
public enum LocalPreviewFixtures {
    public struct Response {
        public let statusCode: Int
        public let data: Data
    }
    public static let actorID = "local-preview-actor"
    public static func response(method: String, path: String) -> Response {
        guard method == "GET" else { return unavailable }
        let ownedCards = [card(id: "preview-note", owned: true, index: 0), card(id: "preview-note-2", owned: true, index: 1)]
        let cards = (0..<6).map { card(id: $0 == 0 ? "preview-field-note" : "preview-field-note-\($0)", owned: false, index: $0) }
        let allCards = ownedCards + cards
        if path == "/api/cards/preview-field-note/comments" {
            let comment = ["comment_id": "preview-reply", "card_id": "preview-field-note", "actor_id": "preview-reader",
                           "username": "Mira Chen", "body": "I saved this passage too.", "created_at": "2026-10-26T09:00:00Z"]
            return json(["success": true, "data": [comment], "meta": pageMetadata(total: 1)])
        }
        if path.hasPrefix("/api/cards/"), !path.hasSuffix("/links"),
           let selected = allCards.first(where: { "/api/cards/" + ($0["id"] as? String ?? "") == path }) {
            return json(["success": true, "data": selected])
        }
        if allCards.contains(where: { "/api/cards/" + ($0["id"] as? String ?? "") + "/links" == path }) {
            return json(["success": true, "data": ["outgoing_links": [], "incoming_links": [], "linked_cards": []]])
        }
        if let index = sampleAuthors.indices.first(where: { path == "/api/v1/profile/\(sampleAuthorID($0))" }) {
            return json(["success": true, "data": actorSummary(sampleAuthorID(index))])
        }
        if let index = sampleAuthors.indices.first(where: { path == "/api/v1/profile/\(sampleAuthorID($0))/cards" }) {
            let published = cards.filter { $0["owner_actor_id"] as? String == sampleAuthorID(index) }
            return json(["success": true, "data": published, "meta": pageMetadata(total: published.count)])
        }
        for actor in knownActorIDs {
            if path == "/api/v1/actors/\(actor)/followers" || path == "/api/v1/actors/\(actor)/following" {
                let ids = path.hasSuffix("/followers") ? followerIDs(of: actor) : followingIDs(of: actor)
                return json(["success": true, "data": ["items": ids.map(actorSummary), "next_cursor": "", "has_more": false]])
            }
        }
        let pagination = pageMetadata(total: 6)
        let data: Any
        switch path {
        case "/api/cards":
            return json(["success": true, "data": ownedCards, "meta": pagination.merging(["total": 2]) { _, new in new }])
        case "/api/v1/explore/recommended":
            return json(["success": true, "data": cards, "meta": pagination])
        case "/api/v1/explore/search":
            // Search exposes the same fixed public samples for UI inspection;
            // this transport does not simulate server ranking or query matching.
            let searchCards = cards.map { card -> [String: Any] in
                var result = card
                var author = card["author"] as? [String: Any] ?? [:]
                // SearchAuthor's existing decoder requires this field.
                author["avatar_url"] = ""
                result["author"] = author
                return result
            }
            return json(["success": true, "data": searchCards, "meta": pagination])
        case "/api/v1/profile/me", "/api/v1/profile/\(actorID)":
            data = actorSummary(actorID)
        case "/api/v1/profile/me/privacy":
            // PrivacySettingsData has exactly these six existing Boolean fields.
            data = ["show_email": false, "show_phone": false, "show_location": false,
                    "show_birthday": false, "allow_follow": true, "show_follow_lists": true]
        case "/api/user-blocks":
            var blocked = actorSummary(sampleAuthorID(5))
            blocked["blocked_at"] = "2026-10-22T00:00:00Z"
            data = ["items": [blocked], "next_cursor": "", "has_more": false]
        case "/api/cards/trash":
            let trash = (0..<2).map { index -> [String: Any] in
                var sample = card(id: index == 0 ? "preview-trash-note" : "preview-trash-note-2", owned: true, index: index)
                sample["created_at"] = index == 0 ? "2026-09-24T00:00:00Z" : "2026-09-20T00:00:00Z"
                sample["updated_at"] = index == 0 ? "2026-10-23T00:00:00Z" : "2026-10-14T00:00:00Z"
                sample["deleted_at"] = index == 0 ? "2026-10-24T00:00:00Z" : "2026-10-15T00:00:00Z"
                sample["days_remaining"] = index == 0 ? 27 : 18
                return sample
            }
            return json(["success": true, "data": trash, "meta": pageMetadata(total: trash.count)])
        case "/api/chats/conversations":
            data = ["items": [], "pagination": ["page": 1, "per_page": 20, "total": 0, "pages": 0, "has_next": false, "has_prev": false]]
        case "/api/v1/actors/me/favorites":
            return json(["success": true, "data": [], "meta": pagination.merging(["total": 0]) { _, new in new }])
        case "/api/v1/credits/balance":
            data = ["balance": 0, "updated_at": "2026-01-01T09:00:00Z"]
        default: return unavailable
        }
        return json(["success": true, "data": data])
    }

    // Same original sample paragraphs as the approved prototype, used only by the explicit offline transport.
    private static let sampleBodies = [
            "Some ideas need a little room.\n\nI used to think a good note was a finished thought. Now I think it is a place to return to. A sentence, a question, something noticed on the way home.\n\nWhat if we leave the edges open? Give an idea enough space to meet another one. Let the connection arrive before the conclusion.\n\nToday, I’m keeping the unfinished things.",
            "A small ritual for noticing.\n\nBefore opening another tab, write down the question you are carrying. One line is enough.\n\nIt changes how you read. You begin to find your own thread through other people’s thinking.",
            "Attention is a kind of generosity.\n\nThere is a different way to move through the world: a little slower, with a little more curiosity.\n\nA shadow crossing a page. A conversation that stays with you. An idea that only becomes clear when you share it.\n\nThe things we notice become the things we care about.",
            "A garden is never quite finished.\n\nPerhaps knowledge works the same way. We keep what is growing, make room for what is next, and learn to see a path where there wasn’t one before.\n\nThinking together is a way of tending it.\n\nLast winter I stopped sorting every note into a perfect folder. I began leaving small paths instead: a question beside an observation, a passage beside a drawing. The connections were uneven, but they were mine.\n\nA useful garden has more than one pace. There are places to pause and places to pass through. Some ideas need a season before they become useful; others give something back the day you put them in the ground.\n\nWhen a friend adds a different view, the whole arrangement changes. What looked like a dead end becomes a place to sit. A familiar sentence opens onto another person’s experience.\n\nI still make lists. I still pull weeds. But I no longer mistake a tidy system for a living one. The point is to keep something growing.",
            "Leave a little unfinished.\n\nA line from my notebook after a long conversation. Sharing an idea before it is polished can give someone else a place to begin.",
            "A walk without a destination.\n\nA small field guide for an ordinary afternoon. These are the observations I brought home.",
            "Small code. A little more calm.\n\nA tiny reminder to keep one deliberate pause between noticing something and turning it into a task.",
            "Keep the question beside the source.\n\nMy margin note: a useful reference tells me where an idea began, and leaves enough room for my own response."
    ]

    private static let sampleAuthors = ["Mira Chen", "Leo Park", "Nia Bell", "Alex Rivers", "Sofia Lane", "Rowan Lee"]
    private static let sampleTags = [["Culture", "Attention"], ["Design", "Connections"], ["Writing", "Ideas"], ["Attention", "Everyday"], ["Code", "Ideas"], ["Reading", "Sources"]]
    // Fixed publication dates make the fixture reproducible; no fabricated live clock.
    private static let sampleDates = ["2026-10-24T00:00:00Z", "2026-10-19T00:00:00Z", "2026-10-25T00:00:00Z", "2026-10-23T00:00:00Z", "2026-10-22T00:00:00Z", "2026-10-19T00:00:00Z"]

    private static func sampleAuthorID(_ index: Int) -> String {
        index == 0 ? "preview-author" : "preview-author-\(index)"
    }

    private static var knownActorIDs: [String] {
        [actorID] + sampleAuthors.indices.map(sampleAuthorID)
    }

    // A fixed sample graph keeps profile counts and their read-only lists consistent.
    // Every actor already exists in the approved offline cards; no remote identity or avatar.
    private static func followingIDs(of id: String) -> [String] {
        switch id {
        case actorID: return [sampleAuthorID(1), sampleAuthorID(2)]
        case sampleAuthorID(0): return [actorID, sampleAuthorID(3)]
        case sampleAuthorID(1): return [actorID]
        case sampleAuthorID(2), sampleAuthorID(3): return [sampleAuthorID(0)]
        case sampleAuthorID(4): return [sampleAuthorID(5)]
        case sampleAuthorID(5): return [sampleAuthorID(4)]
        default: return []
        }
    }

    private static func followerIDs(of id: String) -> [String] {
        knownActorIDs.filter { followingIDs(of: $0).contains(id) }
    }

    private static func actorSummary(_ id: String) -> [String: Any] {
        guard knownActorIDs.contains(id) else { return [:] }
        let authorIndex = sampleAuthors.indices.first { sampleAuthorID($0) == id }
        return ["actor_id": id, "username": authorIndex.map { sampleAuthors[$0] } ?? "Local Preview",
                "bio": id == actorID ? "Sample content · offline" : "Sample author · offline",
                "created_at": "2026-01-01T09:00:00Z", "is_following": followingIDs(of: actorID).contains(id),
                "follower_count": followerIDs(of: id).count, "following_count": followingIDs(of: id).count]
    }

    private static func pageMetadata(total: Int) -> [String: Any] {
        ["page": 1, "per_page": 20, "total": total, "pages": total == 0 ? 0 : 1, "has_next": false, "has_prev": false]
    }

    private static func card(id: String, owned: Bool, index: Int) -> [String: Any] {
        let document = sampleDocument(id: id, owned: owned, index: index)
        let documentJSON = String(data: (try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "[]"
        let authorID = owned ? actorID : sampleAuthorID(index)
        let author = owned ? "You" : sampleAuthors[index]
        let date = owned ? (index == 0 ? "2026-10-26T00:00:00Z" : "2026-10-25T00:00:00Z") : sampleDates[index]
        return ["id": id, "content": sampleHTML(document), "content_json": documentJSON,
         "content_hash": "preview-content-\(id)", "is_public": !owned,
         "tags": owned ? (index == 0 ? ["Writing", "Ideas"] : ["Ideas"]) : sampleTags[index],
         "created_at": date, "updated_at": date,
         "like_count": 0, "comment_count": 0, "favorite_count": 0, "view_count": 0,
         "is_liked": false, "is_pinned": false, "is_favorited": false,
         "is_owner": owned, "owner_actor_id": authorID,
         "rate": owned ? 1 : [1, 3, 9, 27, 81, 243][index],
         "author": ["actor_id": authorID, "author_id": authorID, "username": author, "author_name": author]]
    }

    /// The existing API carries a JSON string containing ordinary BlockNote blocks.
    /// These are the approved prototype's words, not a separate preview view tree.
    private static func sampleDocument(id: String, owned: Bool, index: Int) -> [[String: Any]] {
        let paragraphs = sampleBodies[owned ? index : index + 2].components(separatedBy: "\n\n")
        var blocks: [[String: Any]] = []
        func append(_ type: String, _ text: String, props: [String: Any] = [:]) {
            blocks.append(["id": "\(id)-block-\(blocks.count)", "type": type, "props": props,
                           "content": [["type": "text", "text": text, "styles": [:]]], "children": []])
        }
        if owned {
            // Match the bundled editor's canonical paragraph output so opening
            // an unchanged read-only fixture does not stage a normalization save.
            let paragraphProps = ["backgroundColor": "default", "textColor": "default", "textAlignment": "left"]
            paragraphs.forEach { append("paragraph", $0, props: paragraphProps) }
            return blocks
        }
        switch index {
        case 0:
            // The approved photo is a bundle asset, while AsyncImage uses the
            // default URLSession. Keep this reference text-only and fully offline.
            append("heading", paragraphs[0], props: ["level": 2])
            paragraphs.dropFirst().forEach { append("paragraph", $0) }
        case 1:
            append("heading", paragraphs[0], props: ["level": 2])
            paragraphs.dropFirst().forEach { append("paragraph", $0) }
        case 2:
            append("quote", "An unfinished thought is an invitation to think together.")
            append("paragraph", "Nia Bell · Original sample writing")
            append("heading", paragraphs[0], props: ["level": 2])
            paragraphs.dropFirst().forEach { append("paragraph", $0) }
        case 3:
            append("heading", paragraphs[0], props: ["level": 2])
            for (offset, item) in ["Take the quieter street", "Notice one changing shadow", "Write down a sound", "Bring back a better question"].enumerated() {
                append("checkListItem", item, props: ["checked": offset < 2])
            }
            append("paragraph", "An author’s checklist · 2 of 4 recorded")
            paragraphs.dropFirst().forEach { append("paragraph", $0) }
        case 4:
            append("heading", paragraphs[0], props: ["level": 2])
            append("codeBlock", "struct SmallRitual {\n    let question: String\n\n    var nextStep: String {\n        \"Notice one thing.\"\n    }\n}", props: ["language": "swift"])
            append("paragraph", "A small Swift sketch, saved as a note")
            paragraphs.dropFirst().forEach { append("paragraph", $0) }
        default:
            append("heading", "The Margin Notebook", props: ["level": 2])
            append("quote", "A collection begins with what catches our attention. It becomes understanding when we ask why these things belong together.")
            append("paragraph", "Issue 03 · p. 12")
            append("paragraph", "Fictional publication · Original sample excerpt")
            paragraphs.forEach { append("paragraph", $0) }
        }
        return blocks
    }

    /// Detail currently reads the HTML companion field, so it must contain the
    /// same words and formats as the canonical document returned to the editor.
    private static func sampleHTML(_ document: [[String: Any]]) -> String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        return document.map { block in
            let inline = block["content"] as? [[String: Any]] ?? []
            let text = escape(inline.compactMap { $0["text"] as? String }.joined())
            let props = block["props"] as? [String: Any] ?? [:]
            switch block["type"] as? String {
            case "heading": return "<h2>\(text)</h2>"
            case "quote": return "<blockquote>\(text)</blockquote>"
            case "checkListItem":
                let checked = props["checked"] as? Bool == true ? " checked" : ""
                return "<p><input type=\"checkbox\"\(checked) disabled> \(text)</p>"
            case "codeBlock": return "<pre><code class=\"language-swift\">\(text)</code></pre>"
            default: return "<p>\(text.replacingOccurrences(of: "\n", with: "<br>"))</p>"
            }
        }.joined(separator: "\n")
    }

    private static var unavailable: Response {
        json(["success": false, "code": "local_preview_unavailable", "message": "Local Preview: this action needs a connected service. No request was sent."], statusCode: 503)
    }

    private static func json(_ object: [String: Any], statusCode: Int = 200) -> Response {
        // Every object above contains only JSON-compatible literals.
        Response(statusCode: statusCode, data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
}

#if DEBUG
/// A terminal transport: every URL is answered locally; no fallback session exists.
public final class LocalPreviewURLProtocol: URLProtocol {
    public static let engagementWriteObserved = Notification.Name("localPreview.engagementWriteObserved")
    private var pendingResponse: DispatchWorkItem?
    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    public override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let fixture = LocalPreviewFixtures.response(method: request.httpMethod ?? "GET", path: url.path)
        guard let response = HTTPURLResponse(url: url, statusCode: fixture.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let deliver = DispatchWorkItem { [weak self] in
            guard let self else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: fixture.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        let arguments = ProcessInfo.processInfo.arguments
        let delayedRead = arguments.contains("--ui-test-card-reopen") &&
            ["/api/cards/preview-field-note", "/api/cards/preview-field-note/comments"].contains(url.path)
        let delayedWrite = arguments.contains("--ui-test-card-engagement") &&
            ["POST", "DELETE"].contains(request.httpMethod ?? "") &&
            ["/api/v1/actors/me/favorites", "/api/v1/actors/me/likes"].contains { url.path == $0 || url.path.hasPrefix($0 + "/") }
        if delayedWrite {
            NotificationCenter.default.post(name: Self.engagementWriteObserved, object: nil)
        }
        if delayedRead || delayedWrite {
            pendingResponse = deliver
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: deliver)
        } else {
            deliver.perform()
        }
    }
    public override func stopLoading() {
        pendingResponse?.cancel()
    }
}
#endif
