import Foundation
import Combine

// MARK: 收藏作者模型
struct FavoriteAuthor: Codable {
    let id: Int
    let username: String
    let avatar: String?
}

// MARK: 收藏项目模型
struct FavoriteItem: Codable {
    let id: Int
    let title: String?
    let content: String
    let createdAt: String
    let favoritedAt: String
    let isPinned: Bool
    let pinnedAt: String?
    let favoriteCount: Int?
    let tags: [String]?
    let rate: Int
    let author: FavoriteAuthor
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case createdAt = "created_at"
        case favoritedAt = "favorited_at"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case favoriteCount = "favorite_count"
        case tags
        case author
        case rate
    }
}

// MARK: 分页信息模型
struct PaginationInfo: Codable {
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int
    
    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case total
        case pages
    }
}

// MARK: 收藏列表响应模型
struct FavoritesListResponse: Codable {
    let success: Bool
    let message: String
    let data: [FavoriteItem]
    let pagination: PaginationInfo
}

// MARK: 取消收藏响应数据模型
struct UnfavoriteResponseData: Codable {
    let cardId: Int
    
    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
    }
}

// MARK: 收藏管理器
class FavoritesManager: ObservableObject {
    @Published var favorites: [FavoriteItem] = []
    @Published var isLoading: Bool = false
    @Published var hasMoreData: Bool = true
    @Published var currentPage: Int = 1
    @Published var error: NetworkError?
    
    private let perPage: Int = 20
    private var currentSortBy: String? = "updated_at" // 默认排序字段
    private var currentSortOrder: String? = "desc" // 默认排序顺序
    
    static let shared = FavoritesManager()
    
    private init() {}
    
    // 加载收藏列表
    func loadFavorites(refresh: Bool = false, sortBy: String? = nil, sortOrder: String? = nil) {
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
            favorites.removeAll()
            hasMoreData = true
        }
        
        guard !isLoading && hasMoreData else { return }
        
        isLoading = true
        error = nil
        
        guard let userId = AuthManager.shared.currentUser?.id else {
            error = .unauthorized
            isLoading = false
            return
        }
        
        NetworkManager.shared.getFavorites(
            userId: userId,
            page: currentPage,
            perPage: perPage,
            sortBy: finalSortBy,
            sortOrder: finalSortOrder
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let response):
                    if refresh {
                        self?.favorites = response.data
                    } else {
                        self?.favorites.append(contentsOf: response.data)
                    }
                    
                    // 更新分页信息
                    self?.currentPage = response.pagination.page
                    self?.hasMoreData = response.pagination.page < response.pagination.pages
                    
                case .failure(let error):
                    self?.error = error
                    print("收藏列表加载失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 加载更多收藏
    func loadMoreFavorites() {
        guard hasMoreData && !isLoading else { return }
        currentPage += 1
        loadFavorites() // 使用当前存储的排序参数
    }
    
    // 刷新收藏列表
    func refreshFavorites() {
        loadFavorites(refresh: true)
    }
    
    // 获取收藏总数
    func getFavoritesCount() -> Int {
        return favorites.count
    }
    
    // 取消收藏
    func unfavoriteCard(cardId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = AuthManager.shared.currentUser?.id else {
            completion(.failure(.unauthorized))
            return
        }
        
        
        NetworkManager.shared.unfavoriteCard(cardId: cardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completionResult in
                    if case .failure(let error) = completionResult {
                        print("取消收藏失败: \(error)")
                        completion(.failure(error))
                    }
                },
                receiveValue: { response in
                    if response.success {
                        print("取消收藏成功: cardId=\(cardId)")
                        completion(.success(true))
                    } else {
                        print("取消收藏失败: \(String(describing: response.message))")
                        completion(.failure(.serverError(500, response.message)))
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // 从本地列表中移除收藏项
    func removeFavoriteFromList(cardId: Int) {
        favorites.removeAll { $0.id == cardId }
        print("从本地列表移除收藏项: cardId=\(cardId)")
    }
    
    private var cancellables = Set<AnyCancellable>()
}
