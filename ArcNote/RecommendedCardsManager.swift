import Foundation
import Combine
import SwiftUI

// MARK: - 推荐卡片管理器
class RecommendedCardsManager: ObservableObject {
    @Published var cards: [Card] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?
    
    // 点赞状态管理
    @Published var cardLikeStates: [Int: Bool] = [:] // cardId -> isLiked
    @Published var cardLikeCounts: [Int: Int] = [:] // cardId -> likeCount
    
    // 收藏状态管理
    @Published var cardFavoriteStates: [Int: Bool] = [:] // cardId -> isFavorited
    @Published var cardFavoriteCounts: [Int: Int] = [:] // cardId -> favoriteCount
    
    // 评论数量管理
    @Published var cardCommentCounts: [Int: Int] = [:] // cardId -> commentCount
    
    // 分页管理
    private var currentPage: Int = 1
    private let pageSize: Int = 20
    private var hasMoreData: Bool = true
    private var isLoadingMore: Bool = false
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 当前显示的卡片
    var currentCard: Card? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }
    
    // 是否有下一张卡片
    var hasNextCard: Bool {
        return currentIndex < cards.count - 1
    }
    
    // 是否有上一张卡片
    var hasPreviousCard: Bool {
        return currentIndex > 0
    }
    
    init() {
        loadRecommendedCards()
        setupCommentCountNotification()
    }
    
    // MARK: - 加载推荐卡片
    func loadRecommendedCards(refresh: Bool = false) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            error = .unauthorized
            return
        }
        
        if refresh {
            currentPage = 1
            cards = []
            hasMoreData = true
            currentIndex = 0
        }
        
        guard hasMoreData && !isLoadingMore else {
            print("没有更多数据或正在加载中")
            return
        }
        
        isLoading = refresh ? true : false
        isLoadingMore = !refresh
        error = nil
        
        
        networkManager.getRecommendedCards(userId: userId, limit: pageSize, page: currentPage)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.isLoadingMore = false
                    if case .failure(let error) = completion {
                        self?.error = error
                        print("加载推荐卡片失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    
                    if refresh {
                        self.cards = response.data
                        self.currentIndex = 0
                        // 初始化点赞和收藏状态
                        self.initializeLikeStates()
                        self.initializeFavoriteStates()
                        self.initializeCommentCounts()
                    } else {
                        // 追加数据
                        self.cards.append(contentsOf: response.data)
                        // 更新状态
                        self.updateLikeStates(for: response.data)
                        self.updateFavoriteStates(for: response.data)
                        self.updateCommentCounts(for: response.data)
                    }
                    
                    // 检查是否还有更多数据
                    self.hasMoreData = response.data.count == self.pageSize
                    self.currentPage += 1
                    
                    
//                    for (index, card) in response.data.enumerated() {
//                        let globalIndex = refresh ? index : self.cards.count - response.data.count + index
//                        print("卡片 \(globalIndex): id=\(card.id), author=\(String(describing: card.author))")
//                        if let author = card.author {
//                            print("卡片 \(globalIndex) 作者信息: id=\(author.id), username=\(author.username)")
//                        } else {
//                            print("卡片 \(globalIndex) 作者信息为 nil")
//                        }
//                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 切换到下一张卡片
    func nextCard() {
        guard hasNextCard else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex += 1
        }
        
        // 检查是否需要加载更多数据
        let remainingCards = cards.count - currentIndex - 1
        if remainingCards <= 3 && hasMoreData && !isLoadingMore {
            print("剩余卡片数量: \(remainingCards)，开始加载更多数据")
            loadRecommendedCards(refresh: false)
        }
    }
    
    // MARK: - 切换到上一张卡片
    func previousCard() {
        guard hasPreviousCard else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex -= 1
        }
    }
    
    // MARK: - 处理滑动手势
    func handleSwipeGesture(translation: CGFloat, isEnded: Bool = false) {
        let threshold: CGFloat = 100
        
        if isEnded {
            if abs(translation) > threshold {
                if translation > 0 {
                    // 右滑 上一张
                    previousCard()
                } else {
                    // 左滑 下一张
                    nextCard()
                }
            }
        }
    }
    
    // MARK: 刷新数据
    func refresh() {
        loadRecommendedCards(refresh: true)
    }
    
    // MARK: 重置到第一张卡片
    func resetToFirst() {
        currentIndex = 0
    }
    
    // MARK: 点赞状态管理
    private func initializeLikeStates() {
        for card in cards {
            cardLikeStates[card.id] = card.isLiked ?? false
            cardLikeCounts[card.id] = card.likeCount
        }
    }
    
    // MARK: 收藏状态管理
    private func initializeFavoriteStates() {
        for card in cards {
            cardFavoriteStates[card.id] = card.isFavorited ?? false
            cardFavoriteCounts[card.id] = card.favoriteCount
        }
    }
    
    private func initializeCommentCounts() {
        for card in cards {
            cardCommentCounts[card.id] = card.commentCount
        }
    }
    
    func getFavoriteState(for cardId: Int) -> Bool {
        return cardFavoriteStates[cardId] ?? false
    }
    
    func getFavoriteCount(for cardId: Int) -> Int {
        return cardFavoriteCounts[cardId] ?? 0
    }
    
    // MARK: - 评论数量相关方法
    func getCommentCount(for cardId: Int) -> Int {
        if let count = cardCommentCounts[cardId] {
            return count
        } else {
            // 如果字典中没有记录，从原始卡片数据中获取
            if let card = cards.first(where: { $0.id == cardId }) {
                return card.commentCount
            }
            return 0
        }
    }
    
    func incrementCommentCount(for cardId: Int) {
        let currentCount = cardCommentCounts[cardId] ?? 0
        cardCommentCounts[cardId] = currentCount + 1
    }
    
    // MARK: - 通知设置
    private func setupCommentCountNotification() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CommentCountChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? Int,
                  let newCount = userInfo["newCount"] as? Int else {
                return
            }
            
            // 更新评论数量
            self?.cardCommentCounts[cardId] = newCount
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func getLikeState(for cardId: Int) -> Bool {
        return cardLikeStates[cardId] ?? false
    }
    
    func getLikeCount(for cardId: Int) -> Int {
        return cardLikeCounts[cardId] ?? 0
    }
    
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
    
    func toggleFavorite(for cardId: Int) {
        guard let userId = authManager.currentUser?.id else {
            return
        }
        
        let isCurrentlyFavorited = getFavoriteState(for: cardId)
        let currentCount = cardFavoriteCounts[cardId] ?? 0
        
        if isCurrentlyFavorited {
            // Optimistic update for immediate UI feedback.
            cardFavoriteStates[cardId] = false
            cardFavoriteCounts[cardId] = max(0, currentCount - 1)
            removeFavorite(cardId: cardId, userId: userId) { [weak self] success in
                guard let self = self, !success else { return }
                self.cardFavoriteStates[cardId] = true
                self.cardFavoriteCounts[cardId] = currentCount
            }
        } else {
            // Optimistic update for immediate UI feedback.
            cardFavoriteStates[cardId] = true
            cardFavoriteCounts[cardId] = currentCount + 1
            addFavorite(cardId: cardId, userId: userId) { [weak self] success in
                guard let self = self, !success else { return }
                self.cardFavoriteStates[cardId] = false
                self.cardFavoriteCounts[cardId] = currentCount
            }
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
                        self?.cardLikeCounts[cardId] = max(0, (self?.cardLikeCounts[cardId] ?? 0) - 1)
                        print("取消点赞成功")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func addFavorite(cardId: Int, userId: Int, completion: ((Bool) -> Void)? = nil) {
        networkManager.favoriteCard(cardId: cardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("收藏失败: \(error)")
                        completion?(false)
                    }
                },
                receiveValue: { (response: NetworkResponse<FavoriteResponseData>) in
                    if response.success {
                        print("收藏成功")
                        completion?(true)
                    } else {
                        completion?(false)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func removeFavorite(cardId: Int, userId: Int, completion: ((Bool) -> Void)? = nil) {
        networkManager.unfavoriteCard(cardId: cardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("取消收藏失败: \(error)")
                        completion?(false)
                    }
                },
                receiveValue: { (response: NetworkResponse<UnfavoriteResponseData>) in
                    if response.success {
                        print("取消收藏成功")
                        completion?(true)
                    } else {
                        completion?(false)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 更新状态方法（用于追加数据时）
    private func updateLikeStates(for newCards: [Card]) {
        for card in newCards {
            cardLikeStates[card.id] = card.isLiked ?? false
            cardLikeCounts[card.id] = card.likeCount
        }
    }
    
    private func updateFavoriteStates(for newCards: [Card]) {
        for card in newCards {
            cardFavoriteStates[card.id] = card.isFavorited ?? false
            cardFavoriteCounts[card.id] = card.favoriteCount
        }
    }
    
    private func updateCommentCounts(for newCards: [Card]) {
        for card in newCards {
            cardCommentCounts[card.id] = card.commentCount
        }
    }
}
