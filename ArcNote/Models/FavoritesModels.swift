import Foundation
import Combine

// MARK: 收藏作者模型
struct FavoriteAuthor: Codable {
    let id: String
    let username: String
    let avatar: String?

    init(id: String, username: String, avatar: String?) {
        self.id = id
        self.username = username
        self.avatar = avatar
    }
}

// MARK: 收藏项目模型
struct FavoriteItem: Codable {
    let id: String
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
        case favoriteId = "favorite_id"
        case card
        case favoritedAt = "favorited_at"
        case id
        case title
        case content
        case createdAt = "created_at"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case favoriteCount = "favorite_count"
        case tags
        case author
        case rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        _ = try container.decode(String.self, forKey: .favoriteId)
        let card = try container.decode(Card.self, forKey: .card)
        guard let cardAuthor = card.author else {
            throw DecodingError.keyNotFound(
                CodingKeys.author,
                DecodingError.Context(codingPath: container.codingPath + [CodingKeys.card], debugDescription: "Go CardDTO author is required for favorites")
            )
        }
        guard let cardIsPinned = card.isPinned else {
            throw DecodingError.keyNotFound(
                CodingKeys.isPinned,
                DecodingError.Context(codingPath: container.codingPath + [CodingKeys.card], debugDescription: "Go CardDTO is_pinned is required for favorites")
            )
        }

        id = card.id
        title = card.title
        content = card.content
        createdAt = card.createdAt
        favoritedAt = try container.decode(String.self, forKey: .favoritedAt)
        isPinned = cardIsPinned
        pinnedAt = card.pinnedAt
        favoriteCount = card.favoriteCount
        tags = card.tags
        rate = card.rate
        author = FavoriteAuthor(id: cardAuthor.id, username: cardAuthor.username, avatar: cardAuthor.avatar)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(favoritedAt, forKey: .favoritedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encodeIfPresent(favoriteCount, forKey: .favoriteCount)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encode(rate, forKey: .rate)
        try container.encode(author, forKey: .author)
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
    let message: String?
    let data: [FavoriteItem]
    let meta: PaginationMeta?
    
    var pagination: PaginationInfo {
        let resolved = meta ?? PaginationMeta(total: data.count, page: 1, perPage: data.count)
        return PaginationInfo(page: resolved.page, perPage: resolved.perPage, total: resolved.total, pages: resolved.totalPages)
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
    
    static let shared = FavoritesManager()
    
    private init() {}
    
    // 加载收藏列表
    func loadFavorites(refresh: Bool = false) {
        if refresh {
            currentPage = 1
            favorites.removeAll()
            hasMoreData = true
        }
        
        guard !isLoading && hasMoreData else { return }
        
        isLoading = true
        error = nil
        
        guard AuthManager.shared.currentUser != nil else {
            error = .unauthorized
            isLoading = false
            return
        }
        
        NetworkManager.shared.getFavorites(
            page: currentPage,
            perPage: perPage
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
        loadFavorites()
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
    func unfavoriteCard(cardId: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard AuthManager.shared.currentUser != nil else {
            completion(.failure(.unauthorized))
            return
        }
        
        
        NetworkManager.shared.unfavoriteCard(cardId: cardId)
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
    func removeFavoriteFromList(cardId: String) {
        favorites.removeAll { $0.id == cardId }
        print("从本地列表移除收藏项: cardId=\(cardId)")
    }
    
    private var cancellables = Set<AnyCancellable>()
}
