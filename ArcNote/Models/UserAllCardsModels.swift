import Foundation

// MARK: 用户所有卡片响应模型
struct UserAllCardsResponse: Codable {
    let success: Bool
    let message: String?
    let data: UserAllCardsData
}

struct UserAllCardsData: Codable {
    let ownCards: [UserAllCard]
    let favoritedCards: [UserAllCard]
    let likedCards: [UserAllCard]
    let linkedCards: [UserAllCard]
    let totalCounts: TotalCounts
    
    enum CodingKeys: String, CodingKey {
        case ownCards = "own_cards"
        case favoritedCards = "favorited_cards"
        case likedCards = "liked_cards"
        case linkedCards = "linked_cards"
        case totalCounts = "total_counts"
    }
}

struct UserAllCard: Codable, Identifiable {
    let id: String
    let noteDocumentVersionID: String?
    let title: String?
    let content: String
    let contentJSON: String?
    let backgroundMediaRef: String?
    let contentHash: String
    let tags: [String]
    let isPublic: Bool
    let createdAt: String
    let updatedAt: String
    let ownerActorId: String
    let likeCount: Int
    let favoriteCount: Int
    let commentCount: Int
    let viewCount: Int
    let rate: Int
    let isLiked: Bool?
    let isPinned: Bool?
    let pinnedAt: String?
    let isFavorited: Bool?
    let isOwner: Bool?
    let author: UserAllCardAuthor?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, rate
        case noteDocumentVersionID = "note_document_version_id"
        case contentJSON = "content_json"
        case backgroundMediaRef = "background_media_ref"
        case contentHash = "content_hash"
        case tags
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerActorId = "owner_actor_id"
        case likeCount = "like_count"
        case favoriteCount = "favorite_count"
        case commentCount = "comment_count"
        case viewCount = "view_count"
        case isLiked = "is_liked"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case isFavorited = "is_favorited"
        case isOwner = "is_owner"
        case author
    }

    var libraryUserCard: UserCard {
        UserCard(
            id: id,
            title: title,
            content: content,
            contentJSON: contentJSON,
            backgroundMediaRef: backgroundMediaRef,
            contentHash: contentHash,
            isPublic: isPublic,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked ?? false,
            isPinned: isPinned ?? false,
            pinnedAt: pinnedAt,
            isFavorited: isFavorited,
            favoriteCount: favoriteCount,
            rate: rate,
            ownerActorId: ownerActorId,
            isOwner: isOwner
        )
    }
}

struct UserAllCardAuthor: Codable {
    let id: String
    let username: String
    let avatar: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "author_id"
        case username = "author_name"
        case avatar = "avatar_url"
    }
}

struct TotalCounts: Codable {
    let ownCards: Int
    let favoritedCards: Int
    let likedCards: Int
    let linkedCards: Int
    
    enum CodingKeys: String, CodingKey {
        case ownCards = "own_cards"
        case favoritedCards = "favorited_cards"
        case likedCards = "liked_cards"
        case linkedCards = "linked_cards"
    }
}
