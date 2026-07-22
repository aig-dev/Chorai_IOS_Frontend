import Foundation

public enum CommentVisibility: String, Codable, Equatable, Sendable {
    case publicComment = "public"
    case privateComment = "private"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = value == Self.publicComment.rawValue ? .publicComment : .privateComment
    }
}

public enum CommentTimestamp {
    public static func displayText(for value: String, relativeTo now: Date = Date()) -> String {
        guard let date = parse(value) else { return value }
        let elapsed = max(0, now.timeIntervalSince(date))

        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60))分钟前"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3_600))小时前"
        }
        if elapsed < 604_800 {
            return "\(Int(elapsed / 86_400))天前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let legacyFormatter = DateFormatter()
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        legacyFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return legacyFormatter.date(from: value)
    }
}

public struct CommentUser: Codable, Equatable, Sendable {
    public let id: String
    public let username: String?
    public let avatarUrl: String?

    public var displayName: String {
        guard let candidate = username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty,
              candidate != id,
              !candidate.lowercased().hasPrefix("act_") else {
            return "Chorai user"
        }
        return candidate
    }

    enum CodingKeys: String, CodingKey {
        case actorId = "actor_id"
        case username
        case avatarUrl = "avatar_url"
    }

    public init(id: String, username: String?, avatarUrl: String?) {
        self.id = id
        self.username = username
        self.avatarUrl = avatarUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .actorId)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .actorId)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
    }
}

public struct CommentModel: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let commentAssetId: String?
    public let cardId: String?
    public let parentCommentId: String?
    public let visibility: CommentVisibility
    public let content: String
    public let createdAt: String
    public let updatedAt: String?
    public let user: CommentUser
    public var replies: [CommentModel]

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case commentAssetId = "comment_asset_id"
        case cardId = "card_id"
        case actorId = "actor_id"
        case username
        case avatarUrl = "avatar_url"
        case parentCommentId = "parent_comment_id"
        case visibility
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case replies
    }

    public init(
        id: String,
        commentAssetId: String? = nil,
        cardId: String? = nil,
        parentCommentId: String? = nil,
        visibility: CommentVisibility = .publicComment,
        content: String,
        createdAt: String,
        updatedAt: String?,
        user: CommentUser,
        replies: [CommentModel]
    ) {
        self.id = id
        self.commentAssetId = commentAssetId
        self.cardId = cardId
        self.parentCommentId = parentCommentId
        self.visibility = visibility
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
        self.replies = replies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .commentId)
        commentAssetId = try container.decodeIfPresent(String.self, forKey: .commentAssetId)
        cardId = try container.decodeIfPresent(String.self, forKey: .cardId)
        parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        visibility = try container.decodeIfPresent(CommentVisibility.self, forKey: .visibility) ?? .publicComment
        content = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        user = CommentUser(
            id: try container.decode(String.self, forKey: .actorId),
            username: try container.decodeIfPresent(String.self, forKey: .username),
            avatarUrl: try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        )
        replies = try container.decodeIfPresent([CommentModel].self, forKey: .replies) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .commentId)
        try container.encodeIfPresent(commentAssetId, forKey: .commentAssetId)
        try container.encodeIfPresent(cardId, forKey: .cardId)
        try container.encode(user.id, forKey: .actorId)
        try container.encodeIfPresent(user.username, forKey: .username)
        try container.encodeIfPresent(user.avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(content, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        if !replies.isEmpty {
            try container.encode(replies, forKey: .replies)
        }
    }

    public static func assembleThreads(from comments: [CommentModel]) -> [CommentModel] {
        var orderedIDs: [String] = []
        var commentsByID: [String: CommentModel] = [:]

        for comment in comments where commentsByID[comment.id] == nil {
            var flattened = comment
            flattened.replies = []
            orderedIDs.append(comment.id)
            commentsByID[comment.id] = flattened
        }

        var childrenByParentID: [String: [String]] = [:]
        var rootIDs: [String] = []
        for id in orderedIDs {
            guard let comment = commentsByID[id],
                  let parentID = normalizedParentID(comment.parentCommentId),
                  parentID != id,
                  commentsByID[parentID] != nil else {
                rootIDs.append(id)
                continue
            }
            childrenByParentID[parentID, default: []].append(id)
        }

        func build(_ id: String, ancestors: Set<String>) -> CommentModel? {
            guard var comment = commentsByID[id] else { return nil }
            let nextAncestors = ancestors.union([id])
            comment.replies = childrenByParentID[id, default: []]
                .filter { !nextAncestors.contains($0) }
                .compactMap { build($0, ancestors: nextAncestors) }
            return comment
        }

        var threads = rootIDs.compactMap { build($0, ancestors: []) }
        var representedIDs = Set<String>()
        func collect(_ comment: CommentModel) {
            representedIDs.insert(comment.id)
            comment.replies.forEach(collect)
        }
        threads.forEach(collect)

        for id in orderedIDs where !representedIDs.contains(id) {
            if let thread = build(id, ancestors: []) {
                threads.append(thread)
                collect(thread)
            }
        }
        return threads
    }

    private static func normalizedParentID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
