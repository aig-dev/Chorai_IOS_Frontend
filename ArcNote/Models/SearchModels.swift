import Foundation
import Combine

// MARK: 搜索作者模型
struct SearchAuthor: Codable {
    let id: Int
    let username: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarUrl = "avatar_url"
    }
}

// MARK: 搜索结果卡片模型
struct SearchCard: Codable, Identifiable {
    let id: Int
    let title: String?
    let content: String
    let contentHash: String
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    let favoriteCount: Int
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    let isFavorited: Bool?
    let isPinned: Bool?
    let isLiked: Bool?
    let pinnedAt: String?
    let author: SearchAuthor
    let linkedCards: SearchLinkedCards?
    let rate: Int
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, author, rate
        case contentHash = "content_hash"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case favoriteCount = "favorite_count"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isFavorited = "is_favorited"
        case isPinned = "is_pinned"
        case isLiked = "is_liked"
        case pinnedAt = "pinned_at"
        case linkedCards = "linked_cards"
    }
}

// MARK: 搜索卡片链接模型
struct SearchLinkedCards: Codable {
    let outgoing: [String]
    let incoming: [String]
}

// MARK: 搜索响应模型
struct SearchResponse: Codable {
    let success: Bool
    let message: String
    let data: [SearchCard]
}

// MARK: 搜索管理器
class SearchManager: ObservableObject {
    static let shared = SearchManager()
    
    @Published var searchResults: [SearchCard] = []
    @Published var isLoading: Bool = false
    @Published var hasMoreData: Bool = true
    @Published var currentPage: Int = 1
    @Published var error: NetworkError?
    
    private let perPage: Int = 20
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // 搜索卡片
    func searchCards(query: String, page: Int = 1, completion: @escaping (Result<[SearchCard], NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(.invalidURL))
            return
        }
        
        isLoading = true
        error = nil
        
        networkManager.searchCards(
            query: query,
            userId: userId,
            page: page,
            perPage: perPage
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    if response.success {
                        if page == 1 {
                            self?.searchResults = response.data
                        } else {
                            self?.searchResults.append(contentsOf: response.data)
                        }
                        self?.currentPage = page
                        self?.hasMoreData = response.data.count == self?.perPage
                        completion(.success(response.data))
                    } else {
                        print("搜索失败: \(response.message)")
                        self?.error = .serverError(500, response.message)
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("搜索失败: \(error.localizedDescription)")
                    self?.error = error
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 清空搜索结果
    func clearSearchResults() {
        searchResults = []
        currentPage = 1
        hasMoreData = true
        error = nil
    }
    
    // 加载更多搜索结果
    func loadMoreSearchResults(query: String) {
        guard hasMoreData && !isLoading else { return }
        currentPage += 1
        searchCards(query: query, page: currentPage) { _ in }
    }
}
