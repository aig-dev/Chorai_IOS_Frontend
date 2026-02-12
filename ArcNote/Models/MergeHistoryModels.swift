import Foundation
import Combine

// MARK: 合并历史源卡片作者模型
struct MergeHistoryAuthor: Codable {
    let userId: Int
    let userName: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case userName = "user_name"
    }
}

// MARK: 合并历史源卡片模型
struct MergeHistorySourceCard: Codable, Identifiable {
    let id: Int
    let title: String?
    let content: String
    let contentHash: String
    let tags: [String]
    let isPublic: Bool
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
    let author: MergeHistoryAuthor
    let linkedCards: [String]
    let rate: Int
    let mergeDate: String
    
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
        case mergeDate = "merge_date"
    }
}

// MARK: 合并历史响应模型
struct MergeHistoryResponse: Codable {
    let message: String
    let cardId: Int
    let sourceCards: [MergeHistorySourceCard]
    
    enum CodingKeys: String, CodingKey {
        case message
        case cardId = "card_id"
        case sourceCards = "source_cards"
    }
}

// MARK: 合并历史管理器
class MergeHistoryManager: ObservableObject {
    @Published var mergeHistory: MergeHistoryResponse?
    @Published var isLoading = false
    @Published var error: String?
    
    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    func fetchMergeHistory(cardId: Int, userId: Int, type: String? = nil) {
        isLoading = true
        error = nil
        
        networkManager.getMergeHistory(cardId: cardId, userId: userId, type: type)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("合并历史失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.mergeHistory = response
                    print("合并历史成功: cardId=\(response.cardId), sourceCards=\(response.sourceCards.count), type=\(type ?? "nil")")
                }
            )
            .store(in: &cancellables)
    }
}
