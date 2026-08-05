import Foundation
import Combine

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

// MARK: 相关卡片管理器
class RelatedCardsManager: ObservableObject {
    static let shared = RelatedCardsManager()

    @Published var relatedCards: [RelatedCard] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    // 状态管理
    @Published var cardLikeStates: [String: Bool] = [:]
    @Published var cardLikeCounts: [String: Int] = [:]
    @Published var cardFavoriteStates: [String: Bool] = [:]
    @Published var cardFavoriteCounts: [String: Int] = [:]
    @Published var cardCommentCounts: [String: Int] = [:]

    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // 监听评论数量变化通知
        NotificationCenter.default.publisher(for: NSNotification.Name("CommentCountChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let userInfo = notification.userInfo,
                      let cardId = userInfo["cardId"] as? String,
                      let newCount = userInfo["newCount"] as? Int else {
                    return
                }

                // 更新评论数量
                self?.cardCommentCounts[cardId] = newCount
            }
            .store(in: &cancellables)
    }

    // MARK: 清除缓存
    func clearCache() {
        relatedCards = []
        cardLikeStates = [:]
        cardLikeCounts = [:]
        cardFavoriteStates = [:]
        cardFavoriteCounts = [:]
        cardCommentCounts = [:]
        isLoading = false
        error = nil
    }

    // MARK: 生成相关卡片
    func generateRelatedCards(cardId: String) {
        isLoading = true
        error = nil

        networkManager.generateRelatedCards(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("生成相关卡片失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.isLoading = false
                    if response.success {
                        self?.relatedCards = response.data.relatedCards

                        // 初始化状态
                        for card in response.data.relatedCards {
                            self?.cardLikeStates[card.id] = card.isLiked ?? false
                            self?.cardLikeCounts[card.id] = card.likeCount ?? 0
                            self?.cardFavoriteStates[card.id] = card.isFavorited ?? false
                            self?.cardFavoriteCounts[card.id] = card.favoriteCount ?? 0
                            self?.cardCommentCounts[card.id] = card.commentCount ?? 0
                        }

                    } else {
                        self?.error = response.message
                        print("生成相关卡片失败: \(response.message ?? "未知错误")")
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: 状态获取方法
    func getLikeState(for cardId: String) -> Bool {
        return cardLikeStates[cardId] ?? false
    }

    func getLikeCount(for cardId: String) -> Int {
        return cardLikeCounts[cardId] ?? 0
    }

    func getFavoriteState(for cardId: String) -> Bool {
        return cardFavoriteStates[cardId] ?? false
    }

    func getFavoriteCount(for cardId: String) -> Int {
        return cardFavoriteCounts[cardId] ?? 0
    }

    func getCommentCount(for cardId: String) -> Int {
        return cardCommentCounts[cardId] ?? 0
    }

    // MARK: 点赞功能
    func toggleLike(for cardId: String) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            return
        }

        let isCurrentlyLiked = getLikeState(for: cardId)

        if isCurrentlyLiked {
            unlikeCard(cardId: cardId)
        } else {
            likeCard(cardId: cardId)
        }
    }

    private func likeCard(cardId: String) {
        networkManager.likeCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("点赞失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.cardLikeStates[cardId] = true
                        self?.cardLikeCounts[cardId] = (self?.cardLikeCounts[cardId] ?? 0) + 1
                        print("点赞成功")
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func unlikeCard(cardId: String) {
        networkManager.unlikeCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("取消点赞失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.cardLikeStates[cardId] = false
                        self?.cardLikeCounts[cardId] = max(0, (self?.cardLikeCounts[cardId] ?? 1) - 1)
                        print("取消点赞成功")
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: 收藏功能
    func toggleFavorite(for cardId: String) {
        guard authManager.currentUser != nil else {
            print("用户未登录，无法收藏")
            return
        }
        guard relatedCards.first(where: { $0.id == cardId })?.isOwner != true else {
            return
        }

        let isCurrentlyFavorited = getFavoriteState(for: cardId)

        if isCurrentlyFavorited {
            removeFavorite(cardId: cardId)
        } else {
            addFavorite(cardId: cardId)
        }
    }

    private func addFavorite(cardId: String) {
        networkManager.favoriteCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("收藏失败: \(error)")
                    }
                },
                receiveValue: { [weak self] (response: NetworkResponse<FavoriteResponseData>) in
                    if response.success {
                        self?.cardFavoriteStates[cardId] = true
                        self?.cardFavoriteCounts[cardId] = (self?.cardFavoriteCounts[cardId] ?? 0) + 1
                        print("收藏成功")
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func removeFavorite(cardId: String) {
        networkManager.unfavoriteCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("取消收藏失败: \(error)")
                    }
                },
                receiveValue: { [weak self] (response: NetworkResponse<EmptyResponseData>) in
                    if response.success {
                        self?.cardFavoriteStates[cardId] = false
                        self?.cardFavoriteCounts[cardId] = max(0, (self?.cardFavoriteCounts[cardId] ?? 1) - 1)
                        print("取消收藏成功")
                    }
                }
            )
            .store(in: &cancellables)
    }
}
