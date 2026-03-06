import Foundation

// MARK: 用户所有卡片响应模型
struct UserAllCardsResponse: Codable {
    let success: Bool
    let message: String
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
    let id: Int
    let title: String?
    let content: String
    let contentHash: String
    let labels: String
    let isPublic: Bool
    let createdAt: String
    let updatedAt: String
    let userId: Int
    let likeCount: Int
    let favoriteCount: Int
    let viewCount: Int
    let rate: Int
    let author: UserAllCardAuthor?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, rate
        case contentHash = "content_hash"
        case labels
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case likeCount = "like_count"
        case favoriteCount = "favorite_count"
        case viewCount = "view_count"
        case author
    }
}

struct UserAllCardAuthor: Codable {
    let id: Int
    let username: String
    let avatar: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, avatar
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
