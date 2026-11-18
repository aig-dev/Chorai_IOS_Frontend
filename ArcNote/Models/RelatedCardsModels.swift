import Foundation

// MARK: 相关卡片数据模型
struct RelatedCard: Codable, Identifiable {
    let id: String
    let title: String?
    let content: String
    let contentHash: String?
    let tags: [String]
    let isPublic: Bool
    let likeCount: Int?
    let isLiked: Bool?
    let favoriteCount: Int?
    let isFavorited: Bool?
    let commentCount: Int?
    let createdAt: String
    let updatedAt: String
    let rate: Int
    let isPinned: Bool
    let pinnedAt: String?
    let author: RelatedCardAuthor?
    let ownerActorId: String?
    let isOwner: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, rate
        case contentHash = "content_hash"
        case isPublic = "is_public"
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case favoriteCount = "favorite_count"
        case isFavorited = "is_favorited"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case ownerActorId = "owner_actor_id"
        case isOwner = "is_owner"
        case author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        isLiked = try container.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
        favoriteCount = try container.decodeIfPresent(Int.self, forKey: .favoriteCount) ?? 0
        isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        rate = try container.decodeIfPresent(Int.self, forKey: .rate) ?? 0
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try container.decodeIfPresent(String.self, forKey: .pinnedAt)
        author = try container.decodeIfPresent(RelatedCardAuthor.self, forKey: .author)
        ownerActorId = try container.decodeIfPresent(String.self, forKey: .ownerActorId)
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
    }
}

// MARK: 相关卡片作者信息
struct RelatedCardAuthor: Codable {
    let actorId: String
    let username: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case actorId = "author_id"
        case username = "author_name"
        case avatarUrl = "avatar_url"
    }
}

// MARK: 生成相关卡片响应数据
struct RelatedCardsData: Codable {
    let relatedCards: [RelatedCard]
    let remainingCredit: Int

    enum CodingKeys: String, CodingKey {
        case creditsDeducted = "credits_deducted"
        case groups
    }

    enum GroupKeys: String, CodingKey {
        case related
        case angles
        case keywords
    }

    enum BucketKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remainingCredit = try container.decode(Int.self, forKey: .creditsDeducted)

        let groups = try container.nestedContainer(keyedBy: GroupKeys.self, forKey: .groups)

        var cards: [RelatedCard] = []
        for key in [GroupKeys.related, .angles, .keywords] {
            let bucket = try groups.nestedContainer(keyedBy: BucketKeys.self, forKey: key)
            var items = try bucket.nestedUnkeyedContainer(forKey: .items)

            while !items.isAtEnd {
                let item = try items.decode(SparkRelatedItem.self)
                if let card = item.card {
                    cards.append(card)
                }
            }
        }
        relatedCards = cards
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(remainingCredit, forKey: .creditsDeducted)
    }
}

private struct SparkRelatedItem: Codable {
    let card: RelatedCard?

    enum CodingKeys: String, CodingKey {
        case card
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try container.decodeIfPresent(RelatedCard.self, forKey: .card)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(card, forKey: .card)
    }
}

struct SparkResultItem: Codable, Identifiable {
    let assetId: String
    let versionId: String
    let score: Double
    let origin: String
    let bucket: String
    let resultId: String?
    let modelVersion: String?
    let card: RelatedCard?

    var id: String { resultId ?? "\(assetId)-\(bucket)" }

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case versionId = "version_id"
        case score
        case origin
        case bucket
        case resultId = "result_id"
        case modelVersion = "model_version"
        case card
    }
}

struct SparkResultBucket: Codable {
    let name: String
    let items: [SparkResultItem]
}

struct SparkResultGroups: Codable {
    let related: SparkResultBucket
    let angles: SparkResultBucket
    let keywords: SparkResultBucket
}

struct SparkRunData: Codable {
    let activityId: String
    let rootActivityId: String
    let chainDepth: Int
    let groups: SparkResultGroups

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case rootActivityId = "root_activity_id"
        case chainDepth = "chain_depth"
        case groups
    }
}

struct SparkMoreResponse: Codable {
    let items: [SparkResultItem]
    let nextCursor: String
    let round: Int
    let sourceAssetId: String

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case round
        case sourceAssetId = "source_asset_id"
    }
}

struct SparkActivityResultsResponse: Codable {
    let activityId: String
    let parentActivityId: String?
    let rootActivityId: String
    let chainDepth: Int
    let sourceAssetId: String
    let itemCount: Int
    let resultCount: Int?
    let groupCounts: [String: Int]?
    let groups: SparkResultGroups
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case parentActivityId = "parent_activity_id"
        case rootActivityId = "root_activity_id"
        case chainDepth = "chain_depth"
        case sourceAssetId = "source_asset_id"
        case itemCount = "item_count"
        case resultCount = "result_count"
        case groupCounts = "group_counts"
        case groups
        case createdAt = "created_at"
    }
}

// MARK: 生成相关卡片响应模型
struct GenerateRelatedCardsResponse: Codable {
    let success: Bool
    let message: String?
    let data: RelatedCardsData
}
