import Foundation
import Combine

// MARK: 相关卡片数据模型
struct RelatedCard: Codable, Identifiable {
    let id: Int
    let title: String?
    let content: String
    let tags: [String]
    let likeCount: Int?
    let isLiked: Bool?
    let favoriteCount: Int?
    let isFavorited: Bool?
    let commentCount: Int?
    let createdAt: String
    let author: RelatedCardAuthor?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, tags
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case favoriteCount = "favorite_count"
        case isFavorited = "is_favorited"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case author
    }
}

// MARK: 相关卡片作者信息
struct RelatedCardAuthor: Codable {
    let userId: Int
    let username: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case avatarUrl = "avatar_url"
    }
}

// MARK: 生成相关卡片请求模型
struct GenerateRelatedCardsRequest: Codable {
    let userId: Int
    let cardId: Int
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case cardId = "card_id"
        case count
    }
}

// MARK: 生成相关卡片响应数据
struct RelatedCardsData: Codable {
    let relatedCards: [RelatedCard]
    let remainingCredit: Int
    
    enum CodingKeys: String, CodingKey {
        case relatedCards = "related_cards"
        case remainingCredit = "remaining_credit"
    }
}

// MARK: 生成相关卡片响应模型
struct GenerateRelatedCardsResponse: Codable {
    let success: Bool
    let message: String
    let data: RelatedCardsData
}

// MARK: 相关卡片管理器
class RelatedCardsManager: ObservableObject {
    static let shared = RelatedCardsManager()
    
    @Published var relatedCards: [RelatedCard] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    // 状态管理
    @Published var cardLikeStates: [Int: Bool] = [:]
    @Published var cardLikeCounts: [Int: Int] = [:]
    @Published var cardFavoriteStates: [Int: Bool] = [:]
    @Published var cardFavoriteCounts: [Int: Int] = [:]
    @Published var cardCommentCounts: [Int: Int] = [:]
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 监听评论数量变化通知
        NotificationCenter.default.publisher(for: NSNotification.Name("CommentCountChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let userInfo = notification.userInfo,
                      let cardId = userInfo["cardId"] as? Int,
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
    func generateRelatedCards(userId: Int, cardId: Int, count: Int = 3) {
        isLoading = true
        error = nil
        
        let request = GenerateRelatedCardsRequest(
            userId: userId,
            cardId: cardId,
            count: count
        )
        
        networkManager.generateRelatedCards(request)
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
                        print("生成相关卡片失败: \(response.message)")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 获取合并历史
    func loadMergeHistory(cardId: Int) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            error = "用户未登录"
            return
        }
        
        isLoading = true
        error = nil
        
        print("获取合并历史: cardId=\(cardId), userId=\(userId)")
        
        networkManager.getMergeHistory(cardId: cardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("获取历史失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.isLoading = false
                    print("获取历史成功")
                    
                    // 将合并历史中的源卡片转换为 RelatedCard 格式
                    let relatedCards = response.sourceCards.map { sourceCard in
                        RelatedCard(
                            id: sourceCard.id,
                            title: sourceCard.title,
                            content: sourceCard.content,
                            tags: sourceCard.tags,
                            likeCount: sourceCard.likeCount,
                            isLiked: sourceCard.isLiked,
                            favoriteCount: sourceCard.favoriteCount,
                            isFavorited: sourceCard.isFavorited,
                            commentCount: sourceCard.commentCount,
                            createdAt: sourceCard.createdAt,
                            author: nil // 合并历史中没有作者信息
                        )
                    }
                    
                    self?.relatedCards = relatedCards
                    
                    // 初始化状态
                    for card in relatedCards {
                        self?.cardLikeStates[card.id] = card.isLiked ?? false
                        self?.cardLikeCounts[card.id] = card.likeCount ?? 0
                        self?.cardFavoriteStates[card.id] = card.isFavorited ?? false
                        self?.cardFavoriteCounts[card.id] = card.favoriteCount ?? 0
                        self?.cardCommentCounts[card.id] = card.commentCount ?? 0
                    }
                    
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 状态获取方法
    func getLikeState(for cardId: Int) -> Bool {
        return cardLikeStates[cardId] ?? false
    }
    
    func getLikeCount(for cardId: Int) -> Int {
        return cardLikeCounts[cardId] ?? 0
    }
    
    func getFavoriteState(for cardId: Int) -> Bool {
        return cardFavoriteStates[cardId] ?? false
    }
    
    func getFavoriteCount(for cardId: Int) -> Int {
        return cardFavoriteCounts[cardId] ?? 0
    }
    
    func getCommentCount(for cardId: Int) -> Int {
        return cardCommentCounts[cardId] ?? 0
    }
    
    // MARK: 点赞功能
    func toggleLike(for cardId: Int) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        let isCurrentlyLiked = getLikeState(for: cardId)
        
        if isCurrentlyLiked {
            unlikeCard(cardId: cardId, userId: userId)
        } else {
            likeCard(cardId: cardId, userId: userId)
        }
    }
    
    private func likeCard(cardId: Int, userId: Int) {
        networkManager.likeCard(cardId: cardId, userId: userId)
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
    
    private func unlikeCard(cardId: Int, userId: Int) {
        networkManager.unlikeCard(cardId: cardId, userId: userId)
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
    func toggleFavorite(for cardId: Int) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录，无法收藏")
            return
        }
        
        let isCurrentlyFavorited = getFavoriteState(for: cardId)
        
        if isCurrentlyFavorited {
            removeFavorite(cardId: cardId, userId: userId)
        } else {
            addFavorite(cardId: cardId, userId: userId)
        }
    }
    
    private func addFavorite(cardId: Int, userId: Int) {
        networkManager.favoriteCard(cardId: cardId, userId: userId)
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
    
    private func removeFavorite(cardId: Int, userId: Int) {
        networkManager.unfavoriteCard(cardId: cardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("取消收藏失败: \(error)")
                    }
                },
                receiveValue: { [weak self] (response: NetworkResponse<UnfavoriteResponseData>) in
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
