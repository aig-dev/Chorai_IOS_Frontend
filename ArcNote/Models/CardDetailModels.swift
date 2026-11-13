import Foundation
import Combine
import CoreFlow

// MARK: 卡片详细信息模型
struct CardDetail: Codable {
    let id: String
    let noteDocumentVersionID: String?
    let title: String?
    let content: String
    let contentJSON: String?
    let editorAtmosphere: String?
    let contentHash: String
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    var likeCount: Int
    var isLiked: Bool
    let isPinned: Bool?
    let pinnedAt: String?
    var isFavorited: Bool?
    var favoriteCount: Int?
    let commentCount: Int?
    let rate: Int
    let author: CardDetailAuthor?
    let backgroundMediaRef: String?
    let ownerActorId: String?
    let isOwner: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, rate
        case noteDocumentVersionID = "note_document_version_id"
        case contentJSON = "content_json"
        case editorAtmosphere = "editor_atmosphere"
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
        editorAtmosphere = try container.decodeIfPresent(
            String.self,
            forKey: .editorAtmosphere
        )
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
        ownerActorId = try container.decodeIfPresent(
            String.self,
            forKey: .ownerActorId
        )
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner)
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
@MainActor
final class CardDetailManager: ObservableObject {
    private static let recent = RecentCardReads<CardDetail>()

    @Published private(set) var cardDetail: CardDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var error: NetworkError?

    private var currentCardID: String?
    private var readSession: UInt64?
    private var requestID = UUID()
    private var likeDuringRefresh: CardLikeState?
    private var favoriteDuringRefresh: CardFavoriteState?
    private var subscriptions = Set<AnyCancellable>()

    init(cardID: String? = nil) {
        currentCardID = cardID
        readSession = AuthManager.shared.cardReadSession
        if readSession != nil, let cardID {
            cardDetail = Self.recent.value(for: cardID)
        }
        let center = NotificationCenter.default
        center.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.clearCardDetail()
        }.store(in: &subscriptions)
        center.publisher(for: .cardReadInvalidated).sink { [weak self] event in
            guard let self, let id = event.object as? String, currentCardID == id else { return }
            clearCardDetail()
            error = .notFound
        }.store(in: &subscriptions)
        CardEngagementCenter.shared.likes.sink { [weak self] state in
            guard let self, currentCardID == state.cardID else { return }
            if isLoading { likeDuringRefresh = state }
            cardDetail?.applyLike(state)
        }.store(in: &subscriptions)
        CardEngagementCenter.shared.favorites.sink { [weak self] state in
            guard let self, currentCardID == state.cardID else { return }
            if isLoading { favoriteDuringRefresh = state }
            cardDetail?.applyFavorite(state)
        }.store(in: &subscriptions)
    }

    static func didCommit(_ state: CardLikeState) {
        guard var detail = recent.value(for: state.cardID) else { return }
        detail.applyLike(state)
        recent.insert(detail, for: state.cardID)
    }

    static func didCommit(_ state: CardFavoriteState) {
        guard var detail = recent.value(for: state.cardID) else { return }
        detail.applyFavorite(state)
        recent.insert(detail, for: state.cardID)
    }

    func fetchCardDetail(cardId: String, completion: @escaping (Result<CardDetail, NetworkError>) -> Void) {
        guard let session = AuthManager.shared.cardReadSession else {
            clearCardDetail()
            error = .unauthorized
            completion(.failure(.unauthorized))
            return
        }
        if currentCardID != cardId || readSession != session || cardDetail == nil {
            cardDetail = Self.recent.value(for: cardId)
        }
        currentCardID = cardId
        readSession = session
        error = nil
        isLoading = true
        likeDuringRefresh = nil
        favoriteDuringRefresh = nil
        let request = UUID()
        requestID = request
        NetworkManager.shared.getCardDetail(cardId: cardId, presentsError: false) { [weak self] result in
            guard let self, self.requestID == request, AuthManager.shared.cardReadSession == session else { return }
            self.isLoading = false
            switch result {
            case .success(let response) where response.success && response.data.id == cardId:
                var detail = response.data
                // A receipt delivered after this GET started is newer than its snapshot.
                if let like = self.likeDuringRefresh { detail.applyLike(like) }
                if let favorite = self.favoriteDuringRefresh { detail.applyFavorite(favorite) }
                Self.recent.insert(detail, for: cardId)
                self.cardDetail = detail
                completion(.success(detail))
            case .success:
                self.error = .decodingError
                completion(.failure(.decodingError))
            case .failure(let error):
                if error.invalidatesCardRead {
                    NotificationCenter.default.post(name: .cardReadInvalidated, object: cardId)
                }
                self.error = error
                completion(.failure(error))
            }
        }
    }

    func clearCardDetail() {
        requestID = UUID()
        currentCardID = nil
        readSession = nil
        likeDuringRefresh = nil
        favoriteDuringRefresh = nil
        cardDetail = nil
        isLoading = false
        error = nil
    }
}

private extension CardDetail {
    mutating func applyLike(_ state: CardLikeState) {
        isLiked = state.isLiked
        likeCount = state.likeCount
    }

    mutating func applyFavorite(_ state: CardFavoriteState) {
        let delta = (isFavorited ?? false) == state.isFavorited ? 0 : (state.isFavorited ? 1 : -1)
        favoriteCount = state.favoriteCount ?? max(0, (favoriteCount ?? 0) + delta)
        isFavorited = state.isFavorited
    }
}
