import Foundation
import Combine

// MARK: 评论用户模型
struct CommentUser: Codable {
    let id: Int
    let username: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarUrl = "avatar_url"
    }
}

// MARK: 评论模型
struct CommentModel: Codable, Identifiable {
    let id: Int
    let content: String
    let visibility: String
    let likeCount: Int
    let replyCount: Int?
    let isLiked: Bool
    let createdAt: String
    let updatedAt: String?
    let user: CommentUser
    var replies: [CommentModel]
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case visibility
        case likeCount = "like_count"
        case replyCount = "reply_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
        case replies
    }
    
    // 自定义初始化方法，为回复设置默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(Int.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        visibility = try container.decode(String.self, forKey: .visibility)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        isLiked = try container.decode(Bool.self, forKey: .isLiked)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        user = try container.decode(CommentUser.self, forKey: .user)
        
        // 可选字段，回复可能没有这些字段
        replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        
        // 递归解码replies，为每个回复设置默认的replyCount
        if let repliesData = try? container.decode([CommentModel].self, forKey: .replies) {
            replies = repliesData.map { reply in
                var modifiedReply = reply
                // 为回复设置默认的replyCount为0
                if modifiedReply.replyCount == nil {
                    modifiedReply = CommentModel(
                        id: reply.id,
                        content: reply.content,
                        visibility: reply.visibility,
                        likeCount: reply.likeCount,
                        replyCount: 0,
                        isLiked: reply.isLiked,
                        createdAt: reply.createdAt,
                        updatedAt: reply.updatedAt,
                        user: reply.user,
                        replies: reply.replies
                    )
                }
                return modifiedReply
            }
        } else {
            replies = []
        }
    }
    
    // 手动初始化方法
    init(id: Int, content: String, visibility: String, likeCount: Int, replyCount: Int?, isLiked: Bool, createdAt: String, updatedAt: String?, user: CommentUser, replies: [CommentModel]) {
        self.id = id
        self.content = content
        self.visibility = visibility
        self.likeCount = likeCount
        self.replyCount = replyCount
        self.isLiked = isLiked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
        self.replies = replies
    }
}

// MARK: 创建评论请求模型
struct CreateCommentRequest: Codable {
    let content: String
    let visibility: String
    
    init(content: String, visibility: String = "public") {
        self.content = content
        self.visibility = visibility
    }
}

// MARK: 创建评论响应数据模型
struct CreateCommentData: Codable {
    let id: Int
    let content: String
    let visibility: String
    let likeCount: Int
    let replyCount: Int
    let isLiked: Bool
    let createdAt: String
    let updatedAt: String
    let user: CommentUser
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case visibility
        case likeCount = "like_count"
        case replyCount = "reply_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
    }
}

// MARK: 创建评论响应模型
struct CreateCommentResponse: Codable {
    let success: Bool
    let message: String
    let data: CreateCommentData
}

// MARK: 创建回复请求模型
struct CreateReplyRequest: Codable {
    let content: String
    let visibility: String
    
    init(content: String, visibility: String = "public") {
        self.content = content
        self.visibility = visibility
    }
}

// MARK: 创建回复响应数据模型
struct CreateReplyData: Codable {
    let id: Int
    let content: String
    let visibility: String
    let likeCount: Int
    let isLiked: Bool
    let createdAt: String
    let user: CommentUser
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case visibility
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
        case user
    }
}

// MARK: 创建回复响应模型
struct CreateReplyResponse: Codable {
    let success: Bool
    let message: String
    let data: CreateReplyData
}

// MARK: 评论点赞请求模型
struct CommentLikeRequest: Codable {
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: 评论点赞响应模型
struct CommentLikeResponse: Codable {
    let success: Bool
    let message: String
    let data: CommentLikeData?
}

// MARK: 评论点赞响应数据模型
struct CommentLikeData: Codable {
    let action: String
    
    enum CodingKeys: String, CodingKey {
        case action
    }
}

// MARK: 评论列表响应模型
struct CommentListResponse: Codable {
    let success: Bool
    let message: String
    let data: [CommentModel]
    let total: Int
    let page: Int
    let perPage: Int
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
        case total
        case page
        case perPage = "per_page"
    }
}

// MARK: 评论管理器
class CommentManager: ObservableObject {
    @Published var comments: [CommentModel] = []
    @Published var isLoading: Bool = false
    @Published var hasMoreData: Bool = true
    @Published var currentPage: Int = 1
    
    private let perPage: Int = 20
    private var currentCardId: Int?
    
    // 评论数量变化回调
    var onCommentCountChanged: ((Int, Int) -> Void)? // (cardId, newCount)
    
    // 加载评论
    func loadComments(for cardId: Int, refresh: Bool = false) {
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
    
    // 点赞/取消点赞评论
    func toggleCommentLike(commentId: Int, completion: @escaping (Result<CommentLikeData, NetworkError>) -> Void) {
        guard let userId = AuthManager.shared.currentUser?.id else {
            completion(.failure(.unauthorized))
            return
        }
        
        let request = CommentLikeRequest(userId: userId)
        
        NetworkManager.shared.likeComment(
            commentId: commentId,
            request: request
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let data = response.data {
                        // 根据action更新本地评论数据
                        let isLiked = data.action == "liked"
                        self?.updateCommentLikeStatus(commentId: commentId, isLiked: isLiked)
                        completion(.success(data))
                    } else {
                        completion(.failure(.noData))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 更新评论点赞状态
    private func updateCommentLikeStatus(commentId: Int, isLiked: Bool) {
        // 更新主评论
        if let index = comments.firstIndex(where: { $0.id == commentId }) {
            let currentLikeCount = comments[index].likeCount
            let newLikeCount = isLiked ? currentLikeCount + 1 : max(0, currentLikeCount - 1)
            
            let updatedComment = CommentModel(
                id: comments[index].id,
                content: comments[index].content,
                visibility: comments[index].visibility,
                likeCount: newLikeCount,
                replyCount: comments[index].replyCount,
                isLiked: isLiked,
                createdAt: comments[index].createdAt,
                updatedAt: comments[index].updatedAt,
                user: comments[index].user,
                replies: comments[index].replies
            )
            comments[index] = updatedComment
        } else {
            // 更新子评论
            for i in 0..<comments.count {
                if let replyIndex = comments[i].replies.firstIndex(where: { $0.id == commentId }) {
                    let currentLikeCount = comments[i].replies[replyIndex].likeCount
                    let newLikeCount = isLiked ? currentLikeCount + 1 : max(0, currentLikeCount - 1)
                    
                    let updatedReply = CommentModel(
                        id: comments[i].replies[replyIndex].id,
                        content: comments[i].replies[replyIndex].content,
                        visibility: comments[i].replies[replyIndex].visibility,
                        likeCount: newLikeCount,
                        replyCount: comments[i].replies[replyIndex].replyCount,
                        isLiked: isLiked,
                        createdAt: comments[i].replies[replyIndex].createdAt,
                        updatedAt: comments[i].replies[replyIndex].updatedAt,
                        user: comments[i].replies[replyIndex].user,
                        replies: comments[i].replies[replyIndex].replies
                    )
                    comments[i].replies[replyIndex] = updatedReply
                    break
                }
            }
        }
    }
    
    // 创建评论
    func createComment(for cardId: Int, content: String, visibility: String = "public", completion: @escaping (Result<CommentModel, NetworkError>) -> Void) {
        let request = CreateCommentRequest(content: content, visibility: visibility)
        
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
                        content: response.data.content,
                        visibility: response.data.visibility,
                        likeCount: response.data.likeCount,
                        replyCount: response.data.replyCount,
                        isLiked: response.data.isLiked,
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
    
    // 创建回复
    func createReply(for commentId: Int, content: String, visibility: String = "public", completion: @escaping (Result<CommentModel, NetworkError>) -> Void) {
        let request = CreateReplyRequest(content: content, visibility: visibility)
        
        NetworkManager.shared.createReply(
            commentId: commentId,
            request: request
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // 将CreateReplyData转换为CommentModel
                    let replyModel = CommentModel(
                        id: response.data.id,
                        content: response.data.content,
                        visibility: response.data.visibility,
                        likeCount: response.data.likeCount,
                        replyCount: 0, // 回复没有子回复，所以回复数量为0
                        isLiked: response.data.isLiked,
                        createdAt: response.data.createdAt,
                        updatedAt: response.data.createdAt, // 使用createdAt作为updatedAt
                        user: response.data.user,
                        replies: [] // 回复没有子回复
                    )
                    
                    // 将新回复添加到对应评论的replies中
                    self?.addReplyToComment(commentId: commentId, reply: replyModel)
                    
                    completion(.success(replyModel))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 添加回复到评论
    private func addReplyToComment(commentId: Int, reply: CommentModel) {
        if let index = comments.firstIndex(where: { $0.id == commentId }) {
            comments[index].replies.append(reply)
            // 更新回复数量
            let updatedComment = CommentModel(
                id: comments[index].id,
                content: comments[index].content,
                visibility: comments[index].visibility,
                likeCount: comments[index].likeCount,
                replyCount: comments[index].replies.count,
                isLiked: comments[index].isLiked,
                createdAt: comments[index].createdAt,
                updatedAt: comments[index].updatedAt,
                user: comments[index].user,
                replies: comments[index].replies
            )
            comments[index] = updatedComment
        }
    }
    
    // 删除评论
    func deleteComment(commentId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        NetworkManager.shared.deleteComment(commentId: commentId)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                },
                receiveValue: { [weak self] _ in
                    DispatchQueue.main.async {
                        // 从本地列表中移除评论
                        if let index = self?.comments.firstIndex(where: { $0.id == commentId }) {
                            self?.comments.remove(at: index)
                            
                            // 通知评论数量变化
                            if let cardId = self?.currentCardId {
                                let newCount = self?.comments.count ?? 0
                                self?.onCommentCountChanged?(cardId, newCount)
                            }
                        } else {
                            // 如果是子评论，从父评论的replies中移除
                            for i in 0..<(self?.comments.count ?? 0) {
                                if let replyIndex = self?.comments[i].replies.firstIndex(where: { $0.id == commentId }) {
                                    self?.comments[i].replies.remove(at: replyIndex)
                                    
                                    // 更新回复数量
                                    let updatedComment = CommentModel(
                                        id: self!.comments[i].id,
                                        content: self!.comments[i].content,
                                        visibility: self!.comments[i].visibility,
                                        likeCount: self!.comments[i].likeCount,
                                        replyCount: self!.comments[i].replies.count,
                                        isLiked: self!.comments[i].isLiked,
                                        createdAt: self!.comments[i].createdAt,
                                        updatedAt: self!.comments[i].updatedAt,
                                        user: self!.comments[i].user,
                                        replies: self!.comments[i].replies
                                    )
                                    self?.comments[i] = updatedComment
                                    break
                                }
                            }
                        }
                        
                        completion(.success(true))
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // 删除回复
    func deleteReply(replyId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        NetworkManager.shared.deleteReply(replyId: replyId)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                },
                receiveValue: { [weak self] _ in
                    DispatchQueue.main.async {
                        // 从父评论的replies中移除回复
                        for i in 0..<(self?.comments.count ?? 0) {
                            if let replyIndex = self?.comments[i].replies.firstIndex(where: { $0.id == replyId }) {
                                self?.comments[i].replies.remove(at: replyIndex)
                                
                                // 更新回复数量
                                let updatedComment = CommentModel(
                                    id: self!.comments[i].id,
                                    content: self!.comments[i].content,
                                    visibility: self!.comments[i].visibility,
                                    likeCount: self!.comments[i].likeCount,
                                    replyCount: self!.comments[i].replies.count,
                                    isLiked: self!.comments[i].isLiked,
                                    createdAt: self!.comments[i].createdAt,
                                    updatedAt: self!.comments[i].updatedAt,
                                    user: self!.comments[i].user,
                                    replies: self!.comments[i].replies
                                )
                                self?.comments[i] = updatedComment
                                completion(.success(true))
                                return
                            }
                        }
                        completion(.success(true))
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}
