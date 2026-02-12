import Foundation
import Combine

// MARK: 选择的卡片模型
struct SelectedCard: Codable {
    let id: Int
    let content: String
}

// MARK: 合并卡片请求模型
struct MergeCardsRequest: Codable {
    let userId: Int
    let selectedCards: [SelectedCard]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case selectedCards = "selected_cards"
    }
}

// MARK: 新卡片模型
struct NewCard: Codable {
    let id: Int
    let title: String
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
    let isFavorited: Bool
    let isPinned: Bool
    let isLiked: Bool
    let pinnedAt: String?
    let author: [String: String] // 空对象
    let linkedCards: LinkedCards
    let rate: Int
    let isFollowingAuthor: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, tags
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
        case author
        case linkedCards = "linked_cards"
        case rate
        case isFollowingAuthor = "is_following_author"
    }
}

// MARK: 链接卡片模型
struct LinkedCards: Codable {
    let outgoing: [String]
    let incoming: [String]
}

// MARK: 源卡片模型
struct SourceCard: Codable {
    let id: Int
    let content: String
}

// MARK: 合并卡片响应数据模型
struct MergeCardsData: Codable {
    let newCard: NewCard
    let remainingCredit: Int
    
    enum CodingKeys: String, CodingKey {
        case newCard = "new_card"
        case remainingCredit = "remaining_credit"
    }
}

// MARK: 合并预览响应模型
struct MergePreviewResponse: Codable {
    let success: Bool
    let message: String
    let data: MergeCardsData
}

// MARK: 合并卡片响应模型
struct MergeCardsResponse: Codable {
    let success: Bool
    let message: String
    let data: MergeCardsData
}

// MARK: 合并卡片管理器
class MergeCardsManager: ObservableObject {
    static let shared = MergeCardsManager()
    
    @Published var isMerging: Bool = false
    @Published var mergeResult: MergeCardsData?
    @Published var error: NetworkError?
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // 合并卡片预览
    func mergeCards(selectedCards: [SelectedCard], completion: @escaping (Result<MergePreviewResponse, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录，无法合并卡片")
            completion(.failure(.unauthorized))
            return
        }
        
        isMerging = true
        error = nil
        
        let request = MergeCardsRequest(userId: userId, selectedCards: selectedCards)
        
        networkManager.mergeCards(request: request) { [weak self] result in
            DispatchQueue.main.async {
                self?.isMerging = false
                switch result {
                case .success(let response):
                    print("卡片合并成功: \(response.message)")
                    completion(.success(response))
                case .failure(let error):
                    print("卡片合并失败: \(error.localizedDescription)")
                    self?.error = error
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 清空合并结果
    func clearMergeResult() {
        mergeResult = nil
        error = nil
    }
}
