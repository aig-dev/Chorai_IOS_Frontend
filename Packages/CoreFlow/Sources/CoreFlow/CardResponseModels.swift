import Foundation

public struct CardResponseAuthor: Codable, Equatable, Sendable {
    public let id: String
    public let username: String
    public let avatar: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case actorID = "actor_id"
        case authorID = "author_id"
        case username
        case authorName = "author_name"
        case avatar
        case avatarURL = "avatar_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .authorID)
            ?? container.decodeIfPresent(String.self, forKey: .actorID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .authorName)
            ?? container.decodeIfPresent(String.self, forKey: .username)
            ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatarURL)
            ?? container.decodeIfPresent(String.self, forKey: .avatar)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .authorID)
        try container.encode(username, forKey: .authorName)
        try container.encodeIfPresent(avatar, forKey: .avatarURL)
    }
}

public struct CardResponseData: Codable, Equatable, Sendable {
    public let id: String
    public let noteDocumentVersionID: String?
    public let ownerActorID: String?
    public let title: String?
    public let content: String
    public let contentJSON: String?
    public let backgroundMediaRef: String?
    public let editorAtmosphere: String?
    public let contentHash: String
    public let tags: [String]
    public let isPublic: Bool
    public let createdAt: String
    public let updatedAt: String
    public let favoriteCount: Int
    public let viewCount: Int
    public let likeCount: Int
    public let commentCount: Int
    public let rate: Int
    public let creditScore: Int
    public let isOwner: Bool
    public let isFavorited: Bool
    public let isPinned: Bool
    public let isLiked: Bool
    public let pinnedAt: String?
    public let author: CardResponseAuthor?
    public let isFollowingAuthor: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case noteDocumentVersionID = "note_document_version_id"
        case ownerActorID = "owner_actor_id"
        case title
        case content
        case contentJSON = "content_json"
        case backgroundMediaRef = "background_media_ref"
        case editorAtmosphere = "editor_atmosphere"
        case contentHash = "content_hash"
        case tags
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case favoriteCount = "favorite_count"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case rate
        case creditScore = "credit_score"
        case isOwner = "is_owner"
        case isFavorited = "is_favorited"
        case isPinned = "is_pinned"
        case isLiked = "is_liked"
        case pinnedAt = "pinned_at"
        case author
        case isFollowingAuthor = "is_following_author"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        noteDocumentVersionID = try container.decodeIfPresent(
            String.self,
            forKey: .noteDocumentVersionID
        )
        ownerActorID = try container.decodeIfPresent(
            String.self,
            forKey: .ownerActorID
        )
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        contentJSON = try container.decodeIfPresent(
            String.self,
            forKey: .contentJSON
        )
        backgroundMediaRef = try container.decodeIfPresent(
            String.self,
            forKey: .backgroundMediaRef
        )
        editorAtmosphere = try container.decodeIfPresent(
            String.self,
            forKey: .editorAtmosphere
        )
        contentHash = try container.decodeIfPresent(
            String.self,
            forKey: .contentHash
        ) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPublic = try container.decodeIfPresent(
            Bool.self,
            forKey: .isPublic
        ) ?? false
        createdAt = try container.decodeIfPresent(
            String.self,
            forKey: .createdAt
        ) ?? ""
        updatedAt = try container.decodeIfPresent(
            String.self,
            forKey: .updatedAt
        ) ?? createdAt
        favoriteCount = try container.decodeIfPresent(
            Int.self,
            forKey: .favoriteCount
        ) ?? 0
        viewCount = try container.decodeIfPresent(
            Int.self,
            forKey: .viewCount
        ) ?? 0
        likeCount = try container.decodeIfPresent(
            Int.self,
            forKey: .likeCount
        ) ?? 0
        commentCount = try container.decodeIfPresent(
            Int.self,
            forKey: .commentCount
        ) ?? 0
        rate = try container.decodeIfPresent(Int.self, forKey: .rate) ?? 1
        creditScore = try container.decodeIfPresent(
            Int.self,
            forKey: .creditScore
        ) ?? 0
        isOwner = try container.decodeIfPresent(
            Bool.self,
            forKey: .isOwner
        ) ?? false
        isFavorited = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFavorited
        ) ?? false
        isPinned = try container.decodeIfPresent(
            Bool.self,
            forKey: .isPinned
        ) ?? false
        isLiked = try container.decodeIfPresent(
            Bool.self,
            forKey: .isLiked
        ) ?? false
        pinnedAt = try container.decodeIfPresent(String.self, forKey: .pinnedAt)
        author = try container.decodeIfPresent(
            CardResponseAuthor.self,
            forKey: .author
        )
        isFollowingAuthor = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFollowingAuthor
        ) ?? false
    }
}

public struct CardResponseEnvelope: Codable, Equatable, Sendable {
    public let success: Bool
    public let message: String?
    public let data: CardResponseData

    public init(
        success: Bool,
        message: String?,
        data: CardResponseData
    ) {
        self.success = success
        self.message = message
        self.data = data
    }
}
