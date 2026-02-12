import Foundation
import Combine

// MARK: 卡片详细信息模型
struct CardDetail: Codable {
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
    let isPinned: Bool?
    let pinnedAt: String?
    let isFavorited: Bool?
    let favoriteCount: Int?
    let commentCount: Int?
    let rate: Int
    let author: CardDetailAuthor?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, rate
        case contentHash = "content_hash"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case isFavorited = "is_favorited"
        case favoriteCount = "favorite_count"
        case commentCount = "comment_count"
        case author
    }
}

// MARK: 卡片作者模型
struct CardDetailAuthor: Codable {
    let userId: Int
    let userName: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case userName = "user_name"
        case avatarUrl = "avatar_url"
    }
}

// MARK: 卡片详细信息响应模型
struct CardDetailResponse: Codable {
    let success: Bool
    let message: String
    let data: CardDetail
}

// MARK: 卡片详细信息管理器
class CardDetailManager: ObservableObject {
    static let shared = CardDetailManager()
    
    @Published var cardDetail: CardDetail?
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // 获取卡片详细信息
    func fetchCardDetail(cardId: Int, completion: @escaping (Result<CardDetail, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        isLoading = true
        error = nil
        
        networkManager.getCardDetail(cardId: cardId, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    if response.success {
                        self?.cardDetail = response.data
                        print("详细信息获取成功: \(response.data.title)")
                        completion(.success(response.data))
                    } else {
                        print("详细信息获取失败: \(response.message)")
                        self?.error = .serverError(500, response.message)
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("卡片详细信息获取失败: \(error.localizedDescription)")
                    self?.error = error
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 清空卡片详细信息
    func clearCardDetail() {
        cardDetail = nil
        error = nil
    }
}
