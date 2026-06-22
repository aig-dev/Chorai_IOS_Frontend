import Foundation
import Combine

// MARK: 评论用户模型
struct CommentUser: Codable {
    let id: String
    let username: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case actorId = "actor_id"
        case username
        case avatarUrl = "avatar_url"
    }

    init(id: String, username: String?, avatarUrl: String?) {
        self.id = id
        self.username = username
        self.avatarUrl = avatarUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .actorId)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .actorId)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
    }
}

// MARK: 评论模型
struct CommentModel: Codable, Identifiable {
    let id: String
    let commentAssetId: String?
    let cardId: String?
    let parentCommentId: String?
    let content: String
    let createdAt: String
    let updatedAt: String?
    let user: CommentUser
    var replies: [CommentModel]

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case commentAssetId = "comment_asset_id"
        case cardId = "card_id"
        case actorId = "actor_id"
        case parentCommentId = "parent_comment_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case replies
    }

    // 自定义初始化方法，为回复设置默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .commentId)
        commentAssetId = try container.decode(String.self, forKey: .commentAssetId)
        cardId = try container.decode(String.self, forKey: .cardId)
        parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        content = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        let actorId = try container.decode(String.self, forKey: .actorId)
        user = CommentUser(id: actorId, username: nil, avatarUrl: nil)

        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        replies = []
    }

    // 手动初始化方法
    init(id: String, commentAssetId: String? = nil, cardId: String? = nil, parentCommentId: String? = nil, content: String, createdAt: String, updatedAt: String?, user: CommentUser, replies: [CommentModel]) {
        self.id = id
        self.commentAssetId = commentAssetId
        self.cardId = cardId
        self.parentCommentId = parentCommentId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
        self.replies = replies
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .commentId)
        try container.encodeIfPresent(commentAssetId, forKey: .commentAssetId)
        try container.encodeIfPresent(cardId, forKey: .cardId)
        try container.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try container.encode(content, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

// MARK: 创建评论请求模型
struct CreateCommentRequest: Codable {
    let content: String
    let parentCommentId: String?

    enum CodingKeys: String, CodingKey {
        case content = "body"
        case parentCommentId = "parent_comment_id"
    }

    init(content: String, parentCommentId: String? = nil) {
        self.content = content
        self.parentCommentId = parentCommentId
    }
}

// MARK: 创建评论响应数据模型
struct CreateCommentData: Codable {
    let id: String
    let commentAssetId: String?
    let cardId: String?
    let parentCommentId: String?
    let content: String
    let createdAt: String
    let updatedAt: String?
    let user: CommentUser

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case commentAssetId = "comment_asset_id"
        case cardId = "card_id"
        case actorId = "actor_id"
        case parentCommentId = "parent_comment_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .commentId)
        commentAssetId = try container.decode(String.self, forKey: .commentAssetId)
        cardId = try container.decode(String.self, forKey: .cardId)
        parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        content = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        let actorId = try container.decode(String.self, forKey: .actorId)
        user = CommentUser(id: actorId, username: nil, avatarUrl: nil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .commentId)
        try container.encodeIfPresent(commentAssetId, forKey: .commentAssetId)
        try container.encodeIfPresent(cardId, forKey: .cardId)
        try container.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try container.encode(content, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

// MARK: 创建评论响应模型
struct CreateCommentResponse: Codable {
    let success: Bool
    let message: String?
    let data: CreateCommentData
}

// MARK: 评论列表响应模型
struct CommentListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [CommentModel]
    let meta: PaginationMeta?

    var total: Int { meta?.total ?? data.count }
    var page: Int { meta?.page ?? 1 }
    var perPage: Int { meta?.perPage ?? data.count }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
        case meta
    }
}

// MARK: 评论管理器
class CommentManager: ObservableObject {
    @Published var comments: [CommentModel] = []
    @Published var isLoading: Bool = false
    @Published var hasMoreData: Bool = true
    @Published var currentPage: Int = 1

    private let perPage: Int = 20
    private var currentCardId: String?

    // 评论数量变化回调
    var onCommentCountChanged: ((String, Int) -> Void)? // (cardId, newCount)

    // 加载评论
    func loadComments(for cardId: String, refresh: Bool = false) {
        if refresh {
            currentPage = 1
            hasMoreData = true
            comments = []
        }

        currentCardId = cardId
        isLoading = true

        NetworkManager.shared.getComments(
            cardId: cardId,
            page: currentPage,
            perPage: perPage
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let response):
                    if refresh {
                        self?.comments = response.data
                    } else {
                        self?.comments.append(contentsOf: response.data)
                    }

                    self?.hasMoreData = response.data.count == self?.perPage
                    if self?.hasMoreData == true {
                        self?.currentPage += 1
                    }

                case .failure(let error):
                    print("加载评论失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // 加载更多评论
    func loadMoreComments() {
        guard let cardId = currentCardId, hasMoreData, !isLoading else { return }
        loadComments(for: cardId, refresh: false)
    }

    // 刷新评论
    func refreshComments() {
        guard let cardId = currentCardId else { return }
        loadComments(for: cardId, refresh: true)
    }

    // 获取评论总数
    func getCommentCount() -> Int {
        return comments.count
    }

    // 创建评论
    func createComment(for cardId: String, content: String, completion: @escaping (Result<CommentModel, NetworkError>) -> Void) {
        let request = CreateCommentRequest(content: content)

        NetworkManager.shared.createComment(
            cardId: cardId,
            request: request
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // 将CreateCommentData转换为CommentModel
                    let commentModel = CommentModel(
                        id: response.data.id,
                        commentAssetId: response.data.commentAssetId,
                        cardId: response.data.cardId,
                        parentCommentId: response.data.parentCommentId,
                        content: response.data.content,
                        createdAt: response.data.createdAt,
                        updatedAt: response.data.updatedAt,
                        user: response.data.user,
                        replies: [] // 新创建的评论没有回复
                    )

                    // 将新评论添加到列表顶部
                    self?.comments.insert(commentModel, at: 0)

                    // 通知评论数量变化
                    if let cardId = self?.currentCardId {
                        let newCount = self?.comments.count ?? 0
                        print("数量变化: cardId=\(cardId), newCount=\(newCount)")
                        self?.onCommentCountChanged?(cardId, newCount)
                    }

                    completion(.success(commentModel))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

}
