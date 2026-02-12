import Foundation

// MARK: 辅助结构
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

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

// MARK: 错误响应模型
struct ErrorResponse: Codable {
    let success: Bool
    let message: String?
    let errorCode: String?
    
    enum CodingKeys: String, CodingKey {
        case success, message, errorCode = "error_code"
    }
}

// MARK: 分页响应模型
struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let totalCount: Int
    let page: Int
    let pageSize: Int
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case items, totalCount, page, pageSize, hasMore
    }
}

// MARK: 卡片相关模型
struct Card: Codable, Identifiable {
    let id: Int
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
    let isFavorited: Bool?
    let isLiked: Bool?
    let isPinned: Bool?
    let pinnedAt: String?
    let author: UserInfo?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, contentHash = "content_hash", tags, isPublic = "is_public"
        case createdAt = "created_at", updatedAt = "updated_at", favoriteCount = "favorite_count"
        case likeCount = "like_count", viewCount = "view_count", commentCount = "comment_count"
        case isFavorited = "is_favorited", isLiked = "is_liked", isPinned = "is_pinned"
        case pinnedAt = "pinned_at", author
    }
}

// MARK: 创建卡片请求模型
struct CreateCardRequest: Codable {
    let userId: Int
    let title: String?
    let content: String
    let tags: [String]?
    let isPublic: Bool?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id", title, content, tags
        case isPublic = "is_public"
    }
}

// MARK: 收藏请求模型
struct FavoriteRequest: Codable {
    let userId: Int
    let cardId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case cardId = "card_id"
    }
}

// MARK: 收藏响应数据模型
struct FavoriteResponseData: Codable {
    let cardId: Int
    
    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
    }
}



// MARK: 用户相关模型
struct User: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String
    let avatar: String?
    let bio: String?
    let credit: Int?
    let createdAt: String
    let lastLogin: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, email, avatar, bio, credit
        case createdAt = "created_at", lastLogin = "last_login"
    }
}

// MARK: 用户信息模型
struct UserInfo: Codable, Identifiable {
    let id: Int
    let username: String
    let avatar: String?
    let bio: String?
    let followersCount: Int?
    let followingCount: Int?
    let isFollowing: Bool?
    let followedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, avatar, bio
        case followersCount = "followers_count", followingCount = "following_count"
        case isFollowing = "is_following", followedAt = "followed_at"
    }
}

// MARK: 登录请求模型
struct LoginRequest: Codable {
    let email: String
    let password: String
    
    enum CodingKeys: String, CodingKey {
        case email, password
    }
}

// MARK: 注册请求模型
struct RegisterRequest: Codable {
    let username: String
    let email: String
    let password: String
    let verificationCode: String?
    
    enum CodingKeys: String, CodingKey {
        case username, email, password, verificationCode
    }
}

// MARK: 发送验证码请求模型
struct SendVerificationCodeRequest: Codable {
    let email: String
    
    enum CodingKeys: String, CodingKey {
        case email
    }
}
import SwiftyJSON

// MARK: 认证响应数据模型
struct AuthResponseData: Codable {
    let id: Int
    let email: String
    let username: String
    let createdAt: String
    let isNewUser: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, email, username
        case createdAt = "created_at"
        case isNewUser = "is_new_user"
    }
}

// MARK: 认证响应模型
struct AuthResponse: Codable {
    let success: Bool
    let message: String?
    let data: AuthResponseData?
    let token: String
    
    enum CodingKeys: String, CodingKey {
        case success, message, data, token
    }
}

// MARK: 搜索请求模型
struct SearchRequest: Codable {
    let userId: Int
    let query: String
    let searchType: String?
    let scope: String?
    let sortBy: String?
    let sortOrder: String?
    let tags: [String]?
    let dateFrom: String?
    let dateTo: String?
    let page: Int?
    let perPage: Int?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id", query, searchType = "search_type", scope
        case sortBy = "sort_by", sortOrder = "sort_order", tags
        case dateFrom = "date_from", dateTo = "date_to", page, perPage = "per_page"
    }
}

// MARK: - 卡片列表响应模型
struct CardsListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [Card]
    let total: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message, data, total
    }
}

// MARK: 用户卡片列表响应模型
struct UserCardsListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [UserCard]
    let total: Int
    let page: Int
    let perPage: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message, data, total, page
        case perPage = "per_page"
    }
}

// MARK: 用户卡片数据模型
struct UserCard: Codable, Identifiable {
    let id: Int
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
    let id: Int
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

// MARK: 标签模型
struct Tag: Codable, Identifiable {
    let id: String
    let name: String
    let color: String?
    let noteCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, color, noteCount
    }
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
    let url: String?
    let filename: String?
    let size: Int?
    let mimeType: String?
    
    enum CodingKeys: String, CodingKey {
        case url, filename, size, mimeType = "mime_type"
    }
}

// MARK: 用户响应模型
struct UserResponse: Codable {
    let success: Bool
    let message: String?
    let data: User
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

// MARK: 更新用户资料请求模型
struct UpdateProfileRequest: Codable {
    let username: String?
    let avatar: String?
    let bio: String?
    let location: String?
    let birthday: String?
}

// MARK: 修改密码请求模型
struct ChangePasswordRequest: Codable {
    let oldPassword: String
    let newPassword: String
    
    enum CodingKeys: String, CodingKey {
        case oldPassword = "old_password", newPassword = "new_password"
    }
}


// MARK: 收藏响应模型
struct FavoriteResponse: Codable {
    let success: Bool
    let message: String?
    let data: FavoriteData?
}

struct FavoriteData: Codable {
    let cardId: Int?
    let userId: Int?
    let favoritedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case cardId = "card_id", userId = "user_id", favoritedAt = "favorited_at"
    }
}




// MARK: - 网络错误类型
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case encodingError
    case serverError(Int, String?)
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

// MARK: 新增的数据模型


struct GoogleLoginRequest: Codable {
    let idToken: String
    
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

// MARK: - 批量操作请求/响应
struct BatchRequest: Codable {
    let userId: Int
    let cardIds: [Int]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case cardIds = "card_ids"
    }
}

struct BatchResponse: Codable {
    let success: Bool
    let message: String
    let successCount: Int
    let totalCount: Int
    let failedCards: [[String: Any]]?
    
    enum CodingKeys: String, CodingKey {
        case success, message
        case successCount = "success_count"
        case totalCount = "total_count"
        case failedCards = "failed_cards"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        successCount = try container.decode(Int.self, forKey: .successCount)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        
        // 处理 failedCards 字段
        if var failedCardsContainer = try? container.nestedUnkeyedContainer(forKey: .failedCards) {
            var result: [[String: Any]] = []
            while !failedCardsContainer.isAtEnd {
                if let dictContainer = try? failedCardsContainer.nestedContainer(keyedBy: AnyCodingKey.self) {
                    var dict: [String: Any] = [:]
                    for key in dictContainer.allKeys {
                        if let stringValue = try? dictContainer.decode(String.self, forKey: key) {
                            dict[key.stringValue] = stringValue
                        } else if let intValue = try? dictContainer.decode(Int.self, forKey: key) {
                            dict[key.stringValue] = intValue
                        } else if let boolValue = try? dictContainer.decode(Bool.self, forKey: key) {
                            dict[key.stringValue] = boolValue
                        }
                    }
                    if !dict.isEmpty {
                        result.append(dict)
                    }
                }
            }
            failedCards = result.isEmpty ? nil : result
        } else {
            failedCards = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        try container.encode(successCount, forKey: .successCount)
        try container.encode(totalCount, forKey: .totalCount)
        
        // 处理 failedCards 字段编码
        if let failedCards = failedCards {
            var failedCardsContainer = container.nestedUnkeyedContainer(forKey: .failedCards)
            for dict in failedCards {
                var dictContainer = failedCardsContainer.nestedContainer(keyedBy: AnyCodingKey.self)
                for (key, value) in dict {
                    let codingKey = AnyCodingKey(stringValue: key)!
                    if let stringValue = value as? String {
                        try dictContainer.encode(stringValue, forKey: codingKey)
                    } else if let intValue = value as? Int {
                        try dictContainer.encode(intValue, forKey: codingKey)
                    } else if let boolValue = value as? Bool {
                        try dictContainer.encode(boolValue, forKey: codingKey)
                    }
                }
            }
        }
    }
}


struct RestoreRequest: Codable {
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct CleanupResponse: Codable {
    let success: Bool
    let message: String
    let cleanedCount: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message
        case cleanedCount = "cleaned_count"
    }
}

// MARK: 卡片生成和合并相关
struct GenerateRelatedRequest: Codable {
    let userId: Int
    let cardId: Int
    let count: Int?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case cardId = "card_id"
        case count
    }
}

struct UpdateVisibilityRequest: Codable {
    let userId: Int
    let isPublic: Bool
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isPublic = "is_public"
    }
}


struct CardComment: Codable {
    let id: Int
    let content: String
    let visibility: String
    let likeCount: Int
    let replyCount: Int
    let isLiked: Bool
    let createdAt: String
    let updatedAt: String
    let user: UserInfo
    let replies: [CommentReply]
    
    enum CodingKeys: String, CodingKey {
        case id, content, visibility, user, replies
        case likeCount = "like_count"
        case replyCount = "reply_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommentReply: Codable {
    let id: Int
    let content: String
    let visibility: String
    let likeCount: Int
    let isLiked: Bool
    let createdAt: String
    let user: UserInfo
    
    enum CodingKeys: String, CodingKey {
        case id, content, visibility, user
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
    }
}


struct CreateReply: Codable {
    let userId: Int
    let content: String
    let visibility: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case content, visibility
    }
}

// MARK: 链接相关
struct LinkRequest: Codable {
    let userId: Int
    let linkedCardId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case linkedCardId = "linked_card_id"
    }
}

struct LinkResponse: Codable {
    let success: Bool
    let message: String
    let data: LinkData
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

struct LinkData: Codable {
    let userId: Int
    let cardId: Int
    let linkedCardId: Int
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case cardId = "card_id"
        case linkedCardId = "linked_card_id"
        case createdAt = "created_at"
    }
}

// MARK: 获取卡片链接列表相关模型
struct CardLinksResponse1: Codable {
    let success: Bool
    let message: String
    let data: CardLinksData
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

struct CardLinksData: Codable {
    let outgoingLinks: [CardLinkItem]
    let incomingLinks: [CardLinkItem]
    
    enum CodingKeys: String, CodingKey {
        case outgoingLinks = "outgoing_links"
        case incomingLinks = "incoming_links"
    }
}
struct CardLinkAuthor: Codable {
    let id: Int
    let userName: String
    let avatar: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case userName = "username"
        case avatar = "avatar"
    }
}
struct CardLinkItem: Codable, Identifiable {
    let linkId: Int
    let linkedCardId: Int
    let title: String
    let content: String
    let createdAt: String
    let author: CardLinkAuthor
    
    var id: Int { linkId }
    
    enum CodingKeys: String, CodingKey {
        case author
        case linkId = "link_id"
        case linkedCardId = "linked_card_id"
        case title, content
        case createdAt = "created_at"
    }
}

// MARK: Pin相关
struct PinResponse: Codable {
    let success: Bool
    let message: String
    let data: [String: Any]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        
        // 处理 data 字段
        if let dataContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data) {
            var result: [String: Any] = [:]
            for key in dataContainer.allKeys {
                if let stringValue = try? dataContainer.decode(String.self, forKey: key) {
                    result[key.stringValue] = stringValue
                } else if let intValue = try? dataContainer.decode(Int.self, forKey: key) {
                    result[key.stringValue] = intValue
                } else if let boolValue = try? dataContainer.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = boolValue
                }
            }
            data = result.isEmpty ? nil : result
        } else {
            data = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        
        // 处理 data 字段编码
        if let data = data {
            var dataContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data)
            for (key, value) in data {
                let codingKey = AnyCodingKey(stringValue: key)!
                if let stringValue = value as? String {
                    try dataContainer.encode(stringValue, forKey: codingKey)
                } else if let intValue = value as? Int {
                    try dataContainer.encode(intValue, forKey: codingKey)
                } else if let boolValue = value as? Bool {
                    try dataContainer.encode(boolValue, forKey: codingKey)
                }
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

// MARK: - 用户统计相关
struct StatsResponse: Codable {
    let success: Bool
    let message: String
    let data: UserStats
}

struct UserStats: Codable {
    let totalCards: Int
    let totalFavorites: Int
    let credit: Int
    let rank: Int
    
    enum CodingKeys: String, CodingKey {
        case totalCards = "total_cards"
        case totalFavorites = "total_favorites"
        case credit, rank
    }
}

struct TopUsersResponse: Codable {
    let success: Bool
    let message: String
    let data: [TopUser]
}

struct TopUser: Codable {
    let id: Int
    let username: String
    let avatar: String
    let credit: Int
    let rank: Int
}

struct AvatarUploadResponse: Codable {
    let success: Bool
    let message: String
    let data: [String: Any]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        
        // 处理 data 字段
        if let dataContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data) {
            var result: [String: Any] = [:]
            for key in dataContainer.allKeys {
                if let stringValue = try? dataContainer.decode(String.self, forKey: key) {
                    result[key.stringValue] = stringValue
                } else if let intValue = try? dataContainer.decode(Int.self, forKey: key) {
                    result[key.stringValue] = intValue
                } else if let boolValue = try? dataContainer.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = boolValue
                }
            }
            data = result.isEmpty ? nil : result
        } else {
            data = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        
        // 处理 data 字段编码
        if let data = data {
            var dataContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data)
            for (key, value) in data {
                let codingKey = AnyCodingKey(stringValue: key)!
                if let stringValue = value as? String {
                    try dataContainer.encode(stringValue, forKey: codingKey)
                } else if let intValue = value as? Int {
                    try dataContainer.encode(intValue, forKey: codingKey)
                } else if let boolValue = value as? Bool {
                    try dataContainer.encode(boolValue, forKey: codingKey)
                }
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

// MARK: 收藏相关扩展
struct FavoritesResponse: Codable {
    let success: Bool
    let message: String
    let data: [FavoriteCard]
}

struct FavoriteCard: Codable {
    let id: Int
    let title: String?
    let content: String
    let imageUrl: String?
    let createdAt: String
    let favoritedAt: String
    let isPinned: Bool
    let pinnedAt: String?
    let author: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, author
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case favoritedAt = "favorited_at"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        favoritedAt = try container.decode(String.self, forKey: .favoritedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        pinnedAt = try container.decodeIfPresent(String.self, forKey: .pinnedAt)
        
        // 处理 author 字段
        if let authorContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .author) {
            var result: [String: Any] = [:]
            for key in authorContainer.allKeys {
                if let stringValue = try? authorContainer.decode(String.self, forKey: key) {
                    result[key.stringValue] = stringValue
                } else if let intValue = try? authorContainer.decode(Int.self, forKey: key) {
                    result[key.stringValue] = intValue
                } else if let boolValue = try? authorContainer.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = boolValue
                }
            }
            author = result.isEmpty ? nil : result
        } else {
            author = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(favoritedAt, forKey: .favoritedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        
        // 处理 author 字段编码
        if let author = author {
            var authorContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .author)
            for (key, value) in author {
                let codingKey = AnyCodingKey(stringValue: key)!
                if let stringValue = value as? String {
                    try authorContainer.encode(stringValue, forKey: codingKey)
                } else if let intValue = value as? Int {
                    try authorContainer.encode(intValue, forKey: codingKey)
                } else if let boolValue = value as? Bool {
                    try authorContainer.encode(boolValue, forKey: codingKey)
                }
            }
        }
    }
}

struct UserFavouriteRequest: Codable {
    let userid: Int
    let originid: Int
    let favouriteid: Int
}

struct RelatedCardsResponse: Codable {
    let favouriteId: Int
    let relatedCards: [FavouriteRelation]
    
    enum CodingKeys: String, CodingKey {
        case favouriteId = "favourite_id"
        case relatedCards = "related_cards"
    }
}

struct FavouriteRelation: Codable {
    let favouriteRelationId: Int
    let userId: Int
    let favouriteCard: CardInfo
    let originCard: CardInfo
    
    enum CodingKeys: String, CodingKey {
        case favouriteRelationId = "favourite_relation_id"
        case userId = "user_id"
        case favouriteCard = "favourite_card"
        case originCard = "origin_card"
    }
}

struct CardInfo: Codable {
    let id: Int
    let content: String
    let userId: Int
    let userName: String
    let createdAt: String
    let rate: Int
    
    enum CodingKeys: String, CodingKey {
        case id, content, rate
        case userId = "user_id"
        case userName = "user_name"
        case createdAt = "created_at"
    }
}

// MARK: 关注相关扩展
struct FollowListResponse: Codable {
    let success: Bool
    let message: String
    let data: [UserInfo]
    let total: Int
    let page: Int
    let perPage: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message, data, total, page
        case perPage = "per_page"
    }
}


struct MarkReadRequest: Codable {
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct UnreadCountResponse: Codable {
    let success: Bool
    let message: String
    let unreadCount: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message
        case unreadCount = "unread_count"
    }
}

struct SuccessResponse: Codable {
    let success: Bool
    let message: String
    let data: [String: Any]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        
        // 处理 data 字段
        if let dataContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data) {
            var result: [String: Any] = [:]
            for key in dataContainer.allKeys {
                if let stringValue = try? dataContainer.decode(String.self, forKey: key) {
                    result[key.stringValue] = stringValue
                } else if let intValue = try? dataContainer.decode(Int.self, forKey: key) {
                    result[key.stringValue] = intValue
                } else if let boolValue = try? dataContainer.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = boolValue
                }
            }
            data = result.isEmpty ? nil : result
        } else {
            data = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        
        // 处理 data 字段编码
        if let data = data {
            var dataContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data)
            for (key, value) in data {
                let codingKey = AnyCodingKey(stringValue: key)!
                if let stringValue = value as? String {
                    try dataContainer.encode(stringValue, forKey: codingKey)
                } else if let intValue = value as? Int {
                    try dataContainer.encode(intValue, forKey: codingKey)
                } else if let boolValue = value as? Bool {
                    try dataContainer.encode(boolValue, forKey: codingKey)
                }
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}

struct DeleteNotificationRequest: Codable {
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: 邀请码相关
struct UseInvitationRequest: Codable {
    let userId: Int
    let invitationCode: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case invitationCode = "invitation_code"
    }
}

struct ValidateInvitationRequest: Codable {
    let userId: Int
    let invitationCode: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case invitationCode = "invitation_code"
    }
}

struct GetUserGroupRequest: Codable {
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct GetCodeStatsRequest: Codable {
    let invitationCode: String
    
    enum CodingKeys: String, CodingKey {
        case invitationCode = "invitation_code"
    }
}

// MARK: - 兴趣相关
struct InterestCategoriesResponse: Codable {
    let success: Bool
    let message: String
    let data: [InterestCategory]
}

struct UserInterestsRequest: Codable {
    let userId: Int
    let interestIds: [Int]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case interestIds = "interest_ids"
    }
}

struct UserInterestsResponse: Codable {
    let success: Bool
    let message: String
    let data: [String: Any]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decode(String.self, forKey: .message)
        
        // 处理 data 字段
        if let dataContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data) {
            var result: [String: Any] = [:]
            for key in dataContainer.allKeys {
                if let stringValue = try? dataContainer.decode(String.self, forKey: key) {
                    result[key.stringValue] = stringValue
                } else if let intValue = try? dataContainer.decode(Int.self, forKey: key) {
                    result[key.stringValue] = intValue
                } else if let boolValue = try? dataContainer.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = boolValue
                }
            }
            data = result.isEmpty ? nil : result
        } else {
            data = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        
        // 处理 data 字段编码
        if let data = data {
            var dataContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .data)
            for (key, value) in data {
                let codingKey = AnyCodingKey(stringValue: key)!
                if let stringValue = value as? String {
                    try dataContainer.encode(stringValue, forKey: codingKey)
                } else if let intValue = value as? Int {
                    try dataContainer.encode(intValue, forKey: codingKey)
                } else if let boolValue = value as? Bool {
                    try dataContainer.encode(boolValue, forKey: codingKey)
                }
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case success, message, data
    }
}
