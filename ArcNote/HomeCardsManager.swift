import Foundation
import Combine
import SwiftUI

class HomeCardsManager: ObservableObject {
    @Published var cards: [UserCard] = []
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?
    @Published var hasMoreData: Bool = true
    
    // 收藏状态管理
    @Published var cardFavoriteStates: [Int: Bool] = [:] // cardId -> isFavorited
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentPage: Int = 1
    private let pageSize: Int = 20
    private var currentSortBy: String? = "updated_at" // 默认排序字段
    private var currentSortOrder: String? = "desc" // 默认排序顺序
    
    func loadUserCards(userId: Int? = nil, refresh: Bool = false, sortBy: String? = nil, sortOrder: String? = nil) {
        let targetUserId = userId ?? authManager.currentUser?.id
        guard let targetUserId = targetUserId else {
            error = .unauthorized
            return
        }
        
        // 更新当前排序参数
        if let sortBy = sortBy {
            currentSortBy = sortBy
        }
        if let sortOrder = sortOrder {
            currentSortOrder = sortOrder
        }
        
        // 使用当前排序参数（如果新参数未提供）
        let finalSortBy = sortBy ?? currentSortBy
        let finalSortOrder = sortOrder ?? currentSortOrder
        
        
        if refresh {
            currentPage = 1
            cards = []
            hasMoreData = true
        }
        
        isLoading = true
        error = nil
        
        networkManager.getCards(userId: targetUserId, page: currentPage, perPage: pageSize, sortBy: finalSortBy, sortOrder: finalSortOrder)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error
                        print("获取用户卡片失败: \(error)")
                    }
                    var atsStatus = ""
                    if let atsConfig = Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any] {
                        if let allowsArbitraryLoads = atsConfig["NSAllowsArbitraryLoads"] as? Bool, allowsArbitraryLoads {
                            atsStatus = "ATS 已禁用 (NSAllowsArbitraryLoads = true)"
                        } else {
                            atsStatus = "ATS 未正确配置"
                        }
                    } else {
                        atsStatus = "未找到 ATS 配置"
                    }
                    print(atsStatus)
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    
                    for (index, card) in response.data.enumerated() {
                        print("卡片 \(index): id=\(card.id), commentCount=\(card.commentCount ?? -1), likeCount=\(card.likeCount)")
                    }
                    
                    if refresh {
                        self.cards = response.data
                    } else {
                        self.cards.append(contentsOf: response.data)
                    }
                    
                    self.hasMoreData = response.data.count == self.pageSize
                    self.currentPage += 1
              
                }
            )
            .store(in: &cancellables)
    }
    
    func loadMoreCards() {
        guard hasMoreData && !isLoading else { return }
        loadUserCards(refresh: false)
    }
    
    func refreshCards() {
        loadUserCards(refresh: true)
    }
    
    // MARK: 删除卡片功能
    func deleteCard(cardId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        networkManager.deleteCard(cardId: cardId, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        // 从本地列表中移除卡片
                        self?.cards.removeAll { $0.id == cardId }
                        // 移除收藏状态
                        self?.cardFavoriteStates.removeValue(forKey: cardId)
                        print("卡片删除成功: cardId=\(cardId)")
                        completion(.success(true))
                    } else {
                        print("卡片删除失败: \(response.message)")
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("卡片删除失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 收藏相关方法
    func getFavoriteState(for cardId: Int) -> Bool {
        return cardFavoriteStates[cardId] ?? false
    }
    
    func toggleFavorite(for cardId: Int) {
        guard let userId = authManager.currentUser?.id else {
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
                        print("取消收藏成功")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 切换卡片可见性
    func toggleCardVisibility(cardId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        // 获取当前卡片的可见性状态，然后切换
        guard let currentCard = cards.first(where: { $0.id == cardId }) else {
            print("未找到卡片: cardId=\(cardId)")
            completion(.failure(.serverError(404, "卡片未找到")))
            return
        }
        
        let newIsPublic = !currentCard.isPublic
        
        networkManager.toggleCardVisibility(cardId: cardId, userId: userId, isPublic: newIsPublic) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        // 更新本地卡片数据
                        if let index = self?.cards.firstIndex(where: { $0.id == cardId }) {
                            self?.cards[index] = UserCard(
                                id: self?.cards[index].id ?? 0,
                                title: self?.cards[index].title ?? "",
                                content: self?.cards[index].content ?? "",
                                contentHash: self?.cards[index].contentHash ?? "",
                                isPublic: response.data.isPublic,
                                tags: self?.cards[index].tags ?? [],
                                createdAt: self?.cards[index].createdAt ?? "",
                                updatedAt: self?.cards[index].updatedAt ?? "",
                                likeCount: self?.cards[index].likeCount ?? 0,
                                commentCount: self?.cards[index].commentCount,
                                isLiked: self?.cards[index].isLiked ?? false,
                                isPinned: self?.cards[index].isPinned ?? false,
                                pinnedAt: self?.cards[index].pinnedAt,
                                isFavorited: self?.cards[index].isFavorited,
                                favoriteCount: self?.cards[index].favoriteCount,
                                rate: self?.cards[index].rate ?? 0
                            )
                        }
                        // 刷新Notes列表
                        self?.loadUserCards(refresh: true)
                        completion(.success(true))
                    } else {
                        print("卡片可见性切换失败: \(response.message)")
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("卡片可见性切换失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 切换卡片置顶状态
    func toggleCardPin(cardId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        // 获取当前卡片的置顶状态，然后选择调用Pin还是Unpin API
        guard let currentCard = cards.first(where: { $0.id == cardId }) else {
            print("未找到卡片: cardId=\(cardId)")
            completion(.failure(.serverError(404, "卡片未找到")))
            return
        }
        
        let isCurrentlyPinned = currentCard.isPinned
        print("卡片置顶状态: cardId=\(cardId), 当前状态: \(isCurrentlyPinned)")
        
        // 根据当前状态选择调用Pin还是Unpin API
        let apiCall: (Int, Int, @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) -> Void
        
        if isCurrentlyPinned {
            apiCall = networkManager.unpinCard
        } else {
            apiCall = networkManager.toggleCardPin
        }
        
        apiCall(cardId, userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        // 更新本地卡片数据
                        if let index = self?.cards.firstIndex(where: { $0.id == cardId }) {
                            self?.cards[index] = UserCard(
                                id: self?.cards[index].id ?? 0,
                                title: self?.cards[index].title ?? "",
                                content: self?.cards[index].content ?? "",
                                contentHash: self?.cards[index].contentHash ?? "",
                                isPublic: self?.cards[index].isPublic ?? false,
                                tags: self?.cards[index].tags ?? [],
                                createdAt: self?.cards[index].createdAt ?? "",
                                updatedAt: self?.cards[index].updatedAt ?? "",
                                likeCount: self?.cards[index].likeCount ?? 0,
                                commentCount: self?.cards[index].commentCount,
                                isLiked: self?.cards[index].isLiked ?? false,
                                isPinned: response.data.isPinned,
                                pinnedAt: response.data.pinnedAt,
                                isFavorited: self?.cards[index].isFavorited,
                                favoriteCount: self?.cards[index].favoriteCount,
                                rate: self?.cards[index].rate ?? 0
                            )
                        }
                        print("置顶状态切换成功: cardId=\(cardId), isPinned=\(response.data.isPinned)")
                        // 刷新Notes列表
                        self?.loadUserCards(refresh: true)
                        completion(.success(true))
                    } else {
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
