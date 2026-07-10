import Foundation

// MARK: 网络响应基础模型
struct NetworkResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: T?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case success, message, data, errorCode = "error_code"
    }
}

struct GoAPIErrorEnvelope: Codable {
    let success: Bool?
    let error: GoAPIErrorPayload?
}

struct GoAPIErrorPayload: Codable {
    let code: String?
    let message: String?
}

struct EmptyResponseData: Codable {}

struct HealthResponse: Codable {
    let service: String
    let status: String
}

struct SendVerificationCodeResponse: Codable {
    let success: Bool
    let message: String?
    let code: String?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case success, message, code
        case errorCode = "error_code"
    }
}

struct PaginationMeta: Codable {
    let total: Int
    let page: Int
    let perPage: Int

    var totalPages: Int {
        guard perPage > 0 else { return 0 }
        return (total + perPage - 1) / perPage
    }

    enum CodingKeys: String, CodingKey {
        case total
        case page
        case perPage = "per_page"
    }
}

// MARK: 错误响应模型
struct ErrorResponse: Codable {
    let success: Bool
    let message: String?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case success, message, errorCode = "error_code"
    }
}

// MARK: 卡片相关模型
struct Card: Codable, Identifiable {
    let id: String
    let title: String?
    let content: String
    let contentHash: String?
    let tags: [String]
    let isPublic: Bool
    let createdAt: String
    let updatedAt: String
    let favoriteCount: Int
    let likeCount: Int
    let viewCount: Int
    let commentCount: Int
    let rate: Int
    let isFavorited: Bool?
    let isLiked: Bool?
    let isPinned: Bool?
    let pinnedAt: String?
    let author: UserInfo?

    enum CodingKeys: String, CodingKey {
        case id, title, content, contentHash = "content_hash", tags, isPublic = "is_public"
        case createdAt = "created_at", updatedAt = "updated_at", favoriteCount = "favorite_count"
        case likeCount = "like_count", viewCount = "view_count", commentCount = "comment_count", rate
        case isFavorited = "is_favorited", isLiked = "is_liked", isPinned = "is_pinned"
        case pinnedAt = "pinned_at", author
    }
}

// MARK: 创建卡片请求模型
struct CreateCardRequest: Codable {
    let title: String?
    let content: String
    let tags: [String]?
    let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case title, content, tags
        case isPublic = "is_public"
    }
}

// MARK: 收藏响应数据模型
struct FavoriteResponseData: Codable {
    let favoriteId: String?
    let assetId: String
    let state: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case favoriteId = "favorite_id"
        case assetId = "asset_id"
        case state
        case createdAt = "created_at"
    }
}

struct LikeResponseData: Codable {
    let likeId: String?
    let assetId: String
    let state: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case likeId = "like_id"
        case assetId = "asset_id"
        case state
        case createdAt = "created_at"
    }
}



// MARK: 用户相关模型
struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String
    let avatar: String?
    let bio: String?
    let credit: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, username, email, bio, credit
        case avatar = "avatar_url"
        case createdAt = "created_at"
    }

    init(id: String, username: String, email: String, avatar: String?, bio: String?, credit: Int, createdAt: String) {
        self.id = id
        self.username = username
        self.email = email
        self.avatar = avatar
        self.bio = bio
        self.credit = credit
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decode(String.self, forKey: .email)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        credit = try container.decode(Int.self, forKey: .credit)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(avatar, forKey: .avatar)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encode(credit, forKey: .credit)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: 用户信息模型
struct UserInfo: Codable, Identifiable {
    let id: String
    let username: String
    let avatar: String?
    let bio: String?
    let followersCount: Int?
    let followingCount: Int?
    let isFollowing: Bool?

    enum CodingKeys: String, CodingKey {
        case actorId = "actor_id", authorId = "author_id"
        case username, authorName = "author_name"
        case avatarUrl = "avatar_url", bio
        case followerCount = "follower_count", followingCount = "following_count"
        case isFollowing = "is_following"
    }

    init(id: String, username: String, avatar: String?, bio: String?, followersCount: Int?, followingCount: Int?, isFollowing: Bool?) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.bio = bio
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let actorId = try container.decodeIfPresent(String.self, forKey: .actorId) {
            id = actorId
        } else if let authorId = try container.decodeIfPresent(String.self, forKey: .authorId) {
            id = authorId
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.actorId,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected actor_id or author_id in Go user summary"
                )
            )
        }

        if let actorUsername = try container.decodeIfPresent(String.self, forKey: .username) {
            username = actorUsername
        } else if let authorName = try container.decodeIfPresent(String.self, forKey: .authorName) {
            username = authorName
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.username,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected username or author_name in Go user summary"
                )
            )
        }
        avatar = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followerCount)
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .authorId)
        try container.encode(username, forKey: .authorName)
        try container.encodeIfPresent(avatar, forKey: .avatarUrl)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(followersCount, forKey: .followerCount)
        try container.encodeIfPresent(followingCount, forKey: .followingCount)
        try container.encodeIfPresent(isFollowing, forKey: .isFollowing)
    }
}

// MARK: 认证响应数据模型
struct AuthResponseData: Codable {
    let token: String
    let user: User
    let isNewUser: Bool?

    enum CodingKeys: String, CodingKey {
        case token, user
        case isNewUser = "is_new_user"
    }
}

// MARK: 认证响应模型
struct AuthResponse: Codable {
    let success: Bool
    let message: String?
    let data: AuthResponseData

    var token: String {
        data.token
    }

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

struct VerifyTokenData: Codable {
    let valid: Bool
    let user: User
    let expiresAt: String
    let issuedAt: String

    enum CodingKeys: String, CodingKey {
        case valid, user
        case expiresAt = "expires_at"
        case issuedAt = "issued_at"
    }
}

struct VerifyTokenResponse: Codable {
    let success: Bool
    let message: String?
    let data: VerifyTokenData?
}

struct AuthActionResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: 搜索请求模型
struct SearchRequest: Codable {
    let query: String
    let sortBy: String?
    let sortOrder: String?
    let tags: [String]?
    let page: Int?
    let perPage: Int?

    enum CodingKeys: String, CodingKey {
        case query
        case sortBy = "sort_by"
        case sortOrder = "sort_order"
        case tags, page
        case perPage = "per_page"
    }
}

// MARK: - 卡片列表响应模型
struct CardsListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [Card]
    let meta: PaginationMeta?
    let nextRefreshToken: String?

    var total: Int { meta?.total ?? data.count }

    enum CodingKeys: String, CodingKey {
        case success, message, data, meta
        case nextRefreshToken = "next_refresh_token"
    }
}

// MARK: 用户卡片列表响应模型
struct UserCardsListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [UserCard]
    let meta: PaginationMeta?

    var total: Int { meta?.total ?? data.count }
    var page: Int { meta?.page ?? 1 }
    var perPage: Int { meta?.perPage ?? data.count }

    enum CodingKeys: String, CodingKey {
        case success, message, data, meta
    }
}

// MARK: 用户卡片数据模型
struct UserCard: Codable, Identifiable {
    let id: String
    let title: String?
    let content: String
    let contentHash: String
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    let likeCount: Int
    let commentCount: Int?
    let isLiked: Bool
    let isPinned: Bool
    let pinnedAt: String?
    let isFavorited: Bool?
    let favoriteCount: Int?
    let rate: Int


    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, rate
        case contentHash = "content_hash"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case isFavorited = "is_favorited"
        case favoriteCount = "favorite_count"
    }
}

// MARK: - 创建卡片响应数据模型
struct CreateCardData: Codable {
    let id: String
    let title: String?
    let content: String
    let contentHash: String
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    let likeCount: Int
    let isLiked: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, content, tags
        case contentHash = "content_hash"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case likeCount = "like_count"
        case isLiked = "is_liked"
    }
}

// MARK: 卡片响应模型
struct CardResponse: Codable {
    let success: Bool
    let message: String?
    let data: CreateCardData
}

struct CardMessageData: Codable {
    let message: String?
}

// MARK: 文件上传响应模型
struct UploadResponse: Codable {
    let success: Bool
    let message: String?
    let data: UploadData?

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

struct UploadData: Codable {
    let mediaRef: String
    let publicURL: String
    let bucket: String
    let objectKey: String
    let mime: String
    let sizeBytes: Int
    let sha256: String
    let width: Int?
    let height: Int?
    let assetID: String?
    let uploadKind: String

    enum CodingKeys: String, CodingKey {
        case mediaRef = "media_ref"
        case publicURL = "public_url"
        case bucket
        case objectKey = "object_key"
        case mime
        case sizeBytes = "size_bytes"
        case sha256
        case width
        case height
        case assetID = "asset_id"
        case uploadKind = "upload_kind"
    }
}

// MARK: - 网络错误类型
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case encodingError
    case serverError(Int, String?)
    case api(statusCode: Int, code: String?, message: String?)
    case networkError(Error)
    case unauthorized
    case forbidden
    case notFound
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "InvalidURL"
        case .noData:
            return "NoData"
        case .decodingError:
            return "DecodingError"
        case .encodingError:
            return "EncodingError"
        case .serverError(let code, let message):
            return "Server Error (\(code)): \(message ?? "未知错误")"
        case .api(let statusCode, let code, _):
            return "API Error (\(statusCode)): \(code ?? "UNKNOWN")"
        case .networkError(let error):
            return "NetWord Error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized"
        case .forbidden:
            return "Forbidden"
        case .notFound:
            return "NotFound"
        case .timeout:
            return "Timeout"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: HTTP状态码扩展
extension HTTPURLResponse {
    var isSuccess: Bool {
        return statusCode >= 200 && statusCode < 300
    }

    var isClientError: Bool {
        return statusCode >= 400 && statusCode < 500
    }

    var isServerError: Bool {
        return statusCode >= 500 && statusCode < 600
    }
}

// MARK: 链接相关
struct LinkRequest: Codable {
    let linkedCardId: String

    enum CodingKeys: String, CodingKey {
        case linkedCardId = "linked_card_id"
    }
}

struct LinkResponse: Codable {
    let success: Bool
    let message: String?
    let data: LinkData

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

struct LinkData: Codable {
    let linkId: String
    let cardId: String
    let linkedCardId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case linkId = "note_link_id"
        case sourceAssetId = "source_asset_id"
        case targetAssetId = "target_asset_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkId = try container.decode(String.self, forKey: .linkId)
        cardId = try container.decode(String.self, forKey: .sourceAssetId)
        linkedCardId = try container.decode(String.self, forKey: .targetAssetId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(linkId, forKey: .linkId)
        try container.encode(cardId, forKey: .sourceAssetId)
        try container.encode(linkedCardId, forKey: .targetAssetId)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct CardLinksData: Codable {
    let outgoingLinks: [CardLinkItem]
    let incomingLinks: [CardLinkItem]
    let linkedCards: [Card]

    enum CodingKeys: String, CodingKey {
        case outgoingLinks = "outgoing_links"
        case incomingLinks = "incoming_links"
        case linkedCards = "linked_cards"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkedCards = try container.decodeIfPresent([Card].self, forKey: .linkedCards) ?? []
        let cardsById = linkedCards.reduce(into: [String: Card]()) { result, card in
            result[card.id] = card
        }

        let outgoingEdges = try container.decode([CardLinkItem].self, forKey: .outgoingLinks)
        outgoingLinks = outgoingEdges.map { item in
            item.hydrated(with: cardsById[item.targetAssetId])
        }

        let incomingEdges = try container.decode([CardLinkItem].self, forKey: .incomingLinks)
        incomingLinks = incomingEdges.map { item in
            let relatedAssetId = item.sourceAssetId.isEmpty ? item.linkedCardId : item.sourceAssetId
            let directedItem = CardLinkItem(
                linkId: item.linkId,
                sourceAssetId: item.sourceAssetId,
                targetAssetId: item.targetAssetId,
                linkedCardId: relatedAssetId,
                title: item.title,
                content: item.content,
                createdAt: item.createdAt,
                author: item.author
            )
            return directedItem.hydrated(with: cardsById[relatedAssetId])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outgoingLinks, forKey: .outgoingLinks)
        try container.encode(incomingLinks, forKey: .incomingLinks)
        try container.encode(linkedCards, forKey: .linkedCards)
    }
}

struct ListMyLinksData: Codable {
    let items: [CardLinkItem]
    let total: Int
    let page: Int
    let perPage: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case perPage = "per_page"
        case totalPages = "total_pages"
    }
}
struct CardLinkAuthor: Codable {
    let id: String
    let userName: String
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id = "author_id"
        case userName = "author_name"
        case avatar = "avatar_url"
    }

    init(id: String, userName: String, avatar: String?) {
        self.id = id
        self.userName = userName
        self.avatar = avatar
    }
}
struct CardLinkItem: Codable, Identifiable {
    let linkId: String
    let sourceAssetId: String
    let targetAssetId: String
    let linkedCardId: String
    let title: String?
    let content: String?
    let createdAt: String
    let author: CardLinkAuthor?

    var id: String { linkId }

    enum CodingKeys: String, CodingKey {
        case author
        case noteLinkId = "note_link_id"
        case sourceAssetId = "source_asset_id"
        case targetAssetId = "target_asset_id"
        case title, content
        case createdAt = "created_at"
    }

    init(linkId: String, sourceAssetId: String = "", targetAssetId: String = "", linkedCardId: String, title: String?, content: String?, createdAt: String, author: CardLinkAuthor?) {
        self.linkId = linkId
        self.sourceAssetId = sourceAssetId
        self.targetAssetId = targetAssetId
        self.linkedCardId = linkedCardId
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.author = author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkId = try container.decode(String.self, forKey: .noteLinkId)
        sourceAssetId = try container.decode(String.self, forKey: .sourceAssetId)
        targetAssetId = try container.decode(String.self, forKey: .targetAssetId)
        linkedCardId = targetAssetId.isEmpty ? sourceAssetId : targetAssetId
        title = nil
        content = nil
        createdAt = try container.decode(String.self, forKey: .createdAt)
        author = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(linkId, forKey: .noteLinkId)
        try container.encode(sourceAssetId, forKey: .sourceAssetId)
        try container.encode(targetAssetId, forKey: .targetAssetId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(author, forKey: .author)
    }

    func hydrated(with card: Card?) -> CardLinkItem {
        guard let card = card else {
            return self
        }

        let hydratedAuthor = card.author.map {
            CardLinkAuthor(
                id: $0.id,
                userName: $0.username,
                avatar: $0.avatar
            )
        } ?? author

        return CardLinkItem(
            linkId: linkId,
            sourceAssetId: sourceAssetId,
            targetAssetId: targetAssetId,
            linkedCardId: linkedCardId,
            title: card.title ?? title,
            content: card.content,
            createdAt: createdAt,
            author: hydratedAuthor
        )
    }
}

// MARK: Pin相关
typealias PinResponse = NetworkResponse<Card>

// MARK: - 用户统计相关
struct StatsResponse: Codable {
    let success: Bool
    let message: String?
    let data: UserStats
}

struct UserStats: Codable {
    let cardCount: Int
    let followerCount: Int
    let followingCount: Int

    enum CodingKeys: String, CodingKey {
        case cardCount = "card_count"
        case followerCount = "follower_count"
        case followingCount = "following_count"
    }
}

struct TopUsersResponse: Codable {
    let success: Bool
    let message: String?
    let data: LeaderboardData
}

struct LeaderboardData: Codable {
    let entries: [TopUser]
    let page: Int
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case entries, page
        case perPage = "per_page"
    }
}

struct TopUser: Codable {
    let actorId: String
    let totalCredit: Int
    let cardCount: Int
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case rank
        case actorId = "actor_id"
        case totalCredit = "total_credit"
        case cardCount = "card_count"
    }
}

struct CreditBalanceData: Codable {
    let creditTier: String
    let balance: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case balance
        case creditTier = "credit_tier"
        case updatedAt = "updated_at"
    }
}

struct AvatarUploadResponse: Codable {
    let success: Bool
    let message: String?
    let data: UserProfile

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

// MARK: 关注相关扩展
struct FollowListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [UserInfo]
    let nextCursor: String?
    let hasMore: Bool

    var total: Int { data.count }
    var page: Int { 1 }
    var perPage: Int { data.count }

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }

    enum DataKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }

    init(success: Bool, message: String?, data: [UserInfo], nextCursor: String?, hasMore: Bool) {
        self.success = success
        self.message = message
        self.data = data
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        let dataContainer = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        data = try dataContainer.decode([UserInfo].self, forKey: .items)
        nextCursor = try dataContainer.decode(String.self, forKey: .nextCursor)
        hasMore = try dataContainer.decode(Bool.self, forKey: .hasMore)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(message, forKey: .message)

        var dataContainer = container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        try dataContainer.encode(data, forKey: .items)
        try dataContainer.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try dataContainer.encode(hasMore, forKey: .hasMore)
    }
}


struct UnreadCountResponse: Codable {
    let success: Bool
    let message: String?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case success, message
        case unreadCount = "unread_count"
    }
}

struct SuccessResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: 邀请码相关
struct UseInvitationRequest: Codable {
    let code: String
}

struct ValidateInvitationRequest: Codable {
    let code: String
}

struct InvitationValidateResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationValidateData
}

struct InvitationValidateData: Codable {
    let valid: Bool
}

struct InvitationRedeemResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationRedeemData
}

struct InvitationRedeemData: Codable {
    let invitationRecordId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case invitationRecordId = "invitation_record_id"
        case status
    }
}

struct InvitationReferralResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationReferralData
}

struct InvitationReferralData: Codable {
    let code: String
    let link: String
    let usedCount: Int
    let nextMilestone: Int?

    enum CodingKeys: String, CodingKey {
        case code, link
        case usedCount = "used_count"
        case nextMilestone = "next_milestone"
    }
}

struct InvitationTrackRequest: Codable {
    let code: String
    let deviceFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case code
        case deviceFingerprint = "device_fingerprint"
    }
}

struct InvitationTrackResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationTrackData
}

struct InvitationTrackData: Codable {
    let tracked: Bool
}

struct InvitationRecordsResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationPaginatedData<InvitationRecordItem>
}

struct InvitationRewardsResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationPaginatedData<InvitationRewardItem>
}

struct InvitationPaginatedData<Item: Codable>: Codable {
    let items: [Item]
    let total: Int
    let page: Int
    let limit: Int
}

struct InvitationRecordItem: Codable, Identifiable {
    let invitationRecordId: String
    let inviterActorId: String
    let inviteeActorId: String
    let status: String
    let createdAt: String
    let qualifiedAt: String?
    let rewardedAt: String?

    var id: String { invitationRecordId }

    enum CodingKeys: String, CodingKey {
        case invitationRecordId = "invitation_record_id"
        case inviterActorId = "inviter_actor_id"
        case inviteeActorId = "invitee_actor_id"
        case status
        case createdAt = "created_at"
        case qualifiedAt = "qualified_at"
        case rewardedAt = "rewarded_at"
    }
}

struct InvitationRewardItem: Codable, Identifiable {
    let invitationRewardId: String
    let recipientRole: String
    let creditTier: String
    let amount: Int
    let isMilestoneBonus: Bool
    let status: String
    let createdAt: String

    var id: String { invitationRewardId }

    enum CodingKeys: String, CodingKey {
        case invitationRewardId = "invitation_reward_id"
        case recipientRole = "recipient_role"
        case creditTier = "credit_tier"
        case amount
        case isMilestoneBonus = "is_milestone_bonus"
        case status
        case createdAt = "created_at"
    }
}

struct InterestDomainsData: Codable {
    let domains: [String]
    let interestSelectionCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case domains
        case interestSelectionCompleted = "interest_selection_completed"
    }
}
