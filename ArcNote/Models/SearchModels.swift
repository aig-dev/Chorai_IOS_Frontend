import Foundation
import Combine

// MARK: 搜索作者模型
struct SearchAuthor: Codable {
    let id: String
    let username: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case authorId = "author_id"
        case authorName = "author_name"
        case avatarUrl = "avatar_url"
    }

    init(id: String, username: String, avatarUrl: String?) {
        self.id = id
        self.username = username
        self.avatarUrl = avatarUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .authorId)
        username = try container.decode(String.self, forKey: .authorName)
        avatarUrl = try container.decode(String.self, forKey: .avatarUrl)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .authorId)
        try container.encode(username, forKey: .authorName)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
    }
}

// MARK: 搜索结果卡片模型
struct SearchCard: Codable, Identifiable {
    let id: String
    let noteDocumentVersionID: String?
    let title: String?
    let content: String
    let contentJSON: String?
    let backgroundMediaRef: String?
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
    let ownerActorId: String?
    let isOwner: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case noteDocumentVersionID = "note_document_version_id"
        case title
        case content
        case contentJSON = "content_json"
        case backgroundMediaRef = "background_media_ref"
        case tags
        case author
        case rate
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
        case ownerActorId = "owner_actor_id"
        case isOwner = "is_owner"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        noteDocumentVersionID = try container.decodeIfPresent(
            String.self,
            forKey: .noteDocumentVersionID
        )
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        contentJSON = try container.decodeIfPresent(String.self, forKey: .contentJSON)
        backgroundMediaRef = try container.decodeIfPresent(String.self, forKey: .backgroundMediaRef)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)

        tags = try container.decode([String].self, forKey: .tags)

        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        favoriteCount = try container.decode(Int.self, forKey: .favoriteCount)
        viewCount = try container.decode(Int.self, forKey: .viewCount)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        isFavorited = try container.decode(Bool.self, forKey: .isFavorited)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isLiked = try container.decode(Bool.self, forKey: .isLiked)
        pinnedAt = try container.decodeIfPresent(String.self, forKey: .pinnedAt)
        linkedCards = try container.decodeIfPresent(SearchLinkedCards.self, forKey: .linkedCards)
        rate = try container.decode(Int.self, forKey: .rate)
        author = try container.decode(SearchAuthor.self, forKey: .author)
        ownerActorId = try container.decodeIfPresent(String.self, forKey: .ownerActorId)
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(
            noteDocumentVersionID,
            forKey: .noteDocumentVersionID
        )
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(contentJSON, forKey: .contentJSON)
        try container.encodeIfPresent(backgroundMediaRef, forKey: .backgroundMediaRef)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(isPublic, forKey: .isPublic)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(favoriteCount, forKey: .favoriteCount)
        try container.encode(viewCount, forKey: .viewCount)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encodeIfPresent(isFavorited, forKey: .isFavorited)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(isLiked, forKey: .isLiked)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encode(author, forKey: .author)
        try container.encodeIfPresent(linkedCards, forKey: .linkedCards)
        try container.encode(rate, forKey: .rate)
        try container.encodeIfPresent(ownerActorId, forKey: .ownerActorId)
        try container.encodeIfPresent(isOwner, forKey: .isOwner)
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
    let message: String?
    let data: [SearchCard]
    let meta: PaginationMeta?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        data = try container.decode([SearchCard].self, forKey: .data)
        meta = try container.decodeIfPresent(PaginationMeta.self, forKey: .meta)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(meta, forKey: .meta)
    }
}

// MARK: 搜索管理器
final class ExploreSearchManager: ObservableObject {
    static let shared = ExploreSearchManager()

    @Published var searchResults: [SearchCard] = []
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?

    private let perPage: Int = 20
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var requestID = UUID()
    private var invalidatedDuringRequest = Set<String>()

    private init() {}

    // 搜索卡片
    func searchCards(query: String, completion: @escaping (Result<[SearchCard], NetworkError>) -> Void) {
        guard authManager.currentUser != nil else {
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
        let id = UUID()
        requestID = id
        invalidatedDuringRequest.removeAll()

        networkManager.searchCards(
            query: query,
            page: 1,
            perPage: perPage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                self.isLoading = false
                switch result {
                case .success(let response):
                    if response.success {
                        let cards = response.data.filter { !self.invalidatedDuringRequest.contains($0.id) }
                        self.searchResults = cards
                        completion(.success(cards))
                    } else {
                        print("搜索失败: \(response.message ?? "未知错误")")
                        self.error = .serverError(500, response.message)
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("搜索失败: \(error.localizedDescription)")
                    self.error = error
                    completion(.failure(error))
                }
            }
        }
    }

    // 清空搜索结果
    func clearSearchResults() {
        requestID = UUID()
        invalidatedDuringRequest.removeAll()
        searchResults = []
        isLoading = false
        error = nil
    }

    func invalidateRead(cardID: String) {
        if isLoading { invalidatedDuringRequest.insert(cardID) }
        searchResults.removeAll { $0.id == cardID }
    }
}
