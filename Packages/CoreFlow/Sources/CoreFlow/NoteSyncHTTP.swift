import Foundation

public enum NoteSyncHTTP {
    private struct Envelope<T: Decodable>: Decodable { let success: Bool; let data: T? }
    private struct Card: Decodable {
        let id: String
        let ownerActorID: String
        let syncToken: String
        let lifecycle: NoteLifecycle
        let title: String?
        let content: String
        let contentJSON: String?
        let tags: [String]
        let isPublic: Bool
        let editorAtmosphere: String?
        let backgroundMediaRef: String?
        let isPinned: Bool?
        let createdAt: String?
        let updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case id, title, content, tags, lifecycle
            case ownerActorID = "owner_actor_id", syncToken = "sync_token", contentJSON = "content_json"
            case isPublic = "is_public", editorAtmosphere = "editor_atmosphere", backgroundMediaRef = "background_media_ref"
            case isPinned = "is_pinned"
            case createdAt = "created_at", updatedAt = "updated_at"
        }
    }

    public static func payload<T: Decodable>(_ type: T.Type, from bytes: Data) throws -> T {
        guard let response = try? JSONDecoder().decode(Envelope<T>.self, from: bytes), response.success, let data = response.data else { throw NoteSyncFailure.invalidResponse }
        return data
    }

    public static func snapshot(from bytes: Data, actorID: String) throws -> NoteRemoteSnapshot {
        try snapshot(payload(Card.self, from: bytes), actorID: actorID)
    }

    public static func snapshots(from bytes: Data, actorID: String) throws -> [NoteRemoteSnapshot] {
        try payload([Card].self, from: bytes).map { try snapshot($0, actorID: actorID) }
    }

    private static func snapshot(_ card: Card, actorID: String) throws -> NoteRemoteSnapshot {
        guard card.ownerActorID == actorID, !card.id.isEmpty, !card.syncToken.isEmpty else { throw NoteSyncFailure.invalidResponse }
        return NoteRemoteSnapshot(assetID: card.id, syncToken: card.syncToken,
            body: OfflineNoteBody(title: card.title, content: card.content, contentJSON: card.contentJSON, tags: card.tags),
            lifecycle: card.lifecycle, isPublic: card.isPublic, editorAtmosphere: card.editorAtmosphere ?? "none", backgroundMediaRef: card.backgroundMediaRef, isPinned: card.isPinned,
            createdAt: try timestamp(card.createdAt), updatedAt: try timestamp(card.updatedAt))
    }

    private static func timestamp(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let parsed = CardTimestamp.parse(value) else { throw NoteSyncFailure.invalidResponse }
        return parsed
    }

    public static func receipt(from bytes: Data) throws -> NoteSyncReceipt {
        struct Result: Decodable {
            let receipt: NoteSyncReceipt
            enum CodingKeys: String, CodingKey { case receipt = "sync_receipt" }
        }
        return try payload(Result.self, from: bytes).receipt
    }

    public static func failure(status: Int, body: Data, retryAfter: String?, now: Date = Date()) -> NoteSyncFailure {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let reason = error?["reason"] as? String ?? ""
        if status == 401 { return .authenticationRequired }
        if status == 403 {
            if reason == "note_authority_revoked" { return .authorityRevoked }
            return reason == "account_restricted" ? .accountRestricted : .permissionDenied
        }
        if status == 404 || status == 410 { return .notFound }
        if status == 428 { return .preconditionRequired }
        if status == 503 && reason == "sync_not_ready" {
            if let delay = retryDelay(retryAfter, now: now) { return .transient(retryAfter: delay) }
            return .notReady
        }
        if status == 400 || status == 409 || status == 422 {
            switch reason {
            case "stale_version", "note_authority_changed": return .staleVersion
            case "idempotency_conflict": return .idempotencyConflict
            case "unsupported_document": return .unsupportedDocument
            case "media_expired": return .mediaExpired
            default: return status == 409 ? .invalidResponse : .validation
            }
        }
        if status == 408 || status == 429 || status >= 500 { return .transient(retryAfter: retryDelay(retryAfter, now: now)) }
        return .invalidResponse
    }

    private static func retryDelay(_ value: String?, now: Date) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
