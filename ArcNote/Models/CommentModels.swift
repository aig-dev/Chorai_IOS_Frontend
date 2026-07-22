import Combine
import CoreFlow
import Foundation

typealias CommentUser = CoreFlow.CommentUser
typealias CommentModel = CoreFlow.CommentModel

struct CreateCommentRequest: Codable {
    let content: String
    let parentCommentId: String?
    let visibility: CommentVisibility

    enum CodingKeys: String, CodingKey {
        case content = "body"
        case parentCommentId = "parent_comment_id"
        case visibility
    }

    init(
        content: String,
        parentCommentId: String? = nil,
        visibility: CommentVisibility = .publicComment
    ) {
        self.content = content
        self.parentCommentId = parentCommentId
        self.visibility = visibility
    }
}

typealias CreateCommentData = CoreFlow.CommentModel

struct CreateCommentResponse: Codable {
    let success: Bool
    let message: String?
    let data: CreateCommentData
}

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

final class CommentManager: ObservableObject {
    @Published private(set) var comments: [CommentModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMoreData = true
    @Published private(set) var currentPage = 1
    @Published private(set) var loadedCommentCount = 0

    private let perPage = 20
    private var currentCardId: String?
    private var flatComments: [CommentModel] = []
    private var totalCount = 0

    var onCommentCountChanged: ((String, Int) -> Void)?

    func loadComments(for cardId: String, refresh: Bool = false) {
        if refresh {
            currentPage = 1
            hasMoreData = true
            flatComments = []
            comments = []
            totalCount = 0
            loadedCommentCount = 0
        }

        currentCardId = cardId
        isLoading = true

        NetworkManager.shared.getComments(
            cardId: cardId,
            page: currentPage,
            perPage: perPage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success(let response):
                    if refresh {
                        self.flatComments = self.deduplicated(response.data)
                    } else {
                        self.flatComments = self.deduplicated(self.flatComments + response.data)
                    }
                    self.comments = CommentModel.assembleThreads(from: self.flatComments)
                    self.loadedCommentCount = self.flatComments.count
                    self.totalCount = response.total
                    self.hasMoreData = !response.data.isEmpty && self.flatComments.count < response.total
                    if self.hasMoreData {
                        self.currentPage = response.page + 1
                    }

                case .failure(let error):
                    print("加载评论失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func loadMoreComments() {
        guard let cardId = currentCardId, hasMoreData, !isLoading else { return }
        loadComments(for: cardId)
    }

    func refreshComments() {
        guard let cardId = currentCardId else { return }
        loadComments(for: cardId, refresh: true)
    }

    func getCommentCount() -> Int {
        totalCount
    }

    func createComment(
        for cardId: String,
        content: String,
        parentCommentId: String? = nil,
        visibility: CommentVisibility = .publicComment,
        completion: @escaping (Result<CommentModel, NetworkError>) -> Void
    ) {
        let request = CreateCommentRequest(
            content: content,
            parentCommentId: parentCommentId,
            visibility: visibility
        )

        NetworkManager.shared.createComment(cardId: cardId, request: request) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    guard let self else { return }
                    let comment = response.data
                    if comment.parentCommentId == nil {
                        self.flatComments.insert(comment, at: 0)
                    } else {
                        self.flatComments.append(comment)
                    }
                    self.flatComments = self.deduplicated(self.flatComments)
                    self.comments = CommentModel.assembleThreads(from: self.flatComments)
                    self.loadedCommentCount = self.flatComments.count
                    self.totalCount += 1
                    self.onCommentCountChanged?(cardId, self.totalCount)
                    completion(.success(comment))

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func removeComment(commentId: String) {
        var removedIDs: Set<String> = [commentId]
        var foundDescendant = true
        while foundDescendant {
            foundDescendant = false
            for comment in flatComments {
                guard let parentID = comment.parentCommentId,
                      removedIDs.contains(parentID),
                      !removedIDs.contains(comment.id) else {
                    continue
                }
                removedIDs.insert(comment.id)
                foundDescendant = true
            }
        }

        let previousCount = flatComments.count
        flatComments.removeAll { removedIDs.contains($0.id) }
        let removedCount = previousCount - flatComments.count
        guard removedCount > 0 else { return }

        comments = CommentModel.assembleThreads(from: flatComments)
        loadedCommentCount = flatComments.count
        totalCount = max(0, totalCount - removedCount)
        if let currentCardId {
            onCommentCountChanged?(currentCardId, totalCount)
        }
    }

    private func deduplicated(_ values: [CommentModel]) -> [CommentModel] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}
