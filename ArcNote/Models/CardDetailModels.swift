import Foundation
import Combine

// MARK: 卡片详细信息模型
struct CardDetail: Codable {
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
    let isPinned: Bool?
    let pinnedAt: String?
    let isFavorited: Bool?
    let favoriteCount: Int?
    let commentCount: Int?
    let rate: Int
    let author: CardDetailAuthor?
    let backgroundMediaRef: String?
    
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
        case backgroundMediaRef = "background_media_ref"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        isLiked = try container.decode(Bool.self, forKey: .isLiked)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        pinnedAt = try container.decodeIfPresent(String.self, forKey: .pinnedAt)
        isFavorited = try container.decode(Bool.self, forKey: .isFavorited)
        favoriteCount = try container.decode(Int.self, forKey: .favoriteCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        rate = try container.decode(Int.self, forKey: .rate)
        author = try container.decode(CardDetailAuthor.self, forKey: .author)
        backgroundMediaRef = try container.decodeIfPresent(
            String.self,
            forKey: .backgroundMediaRef
        )
    }
}

// MARK: 卡片作者模型
struct CardDetailAuthor: Codable {
    let actorId: String
    let userName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case actorId = "author_id"
        case userName = "author_name"
        case avatarUrl = "avatar_url"
    }
}

// MARK: 卡片详细信息响应模型
struct CardDetailResponse: Codable {
    let success: Bool
    let message: String?
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
    func fetchCardDetail(cardId: String, completion: @escaping (Result<CardDetail, NetworkError>) -> Void) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        isLoading = true
        error = nil
        
        networkManager.getCardDetail(cardId: cardId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    if response.success {
                        self?.cardDetail = response.data
                        print("详细信息获取成功: \(String(describing: response.data.title))")
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
