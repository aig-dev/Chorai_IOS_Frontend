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

@MainActor
enum CommentService {
    static func loadPage(
        cardID: String, page: Int, perPage: Int, completion: @escaping (CommentPageResult) -> Void
    ) {
        #if DEBUG
        if CommentPresentationFixture.isEnabled {
            let rows = CommentPresentationFixture.comments(for: cardID)
            completion(.page(page == 1 ? rows : [], total: rows.count))
            return
        }
        #endif
        NetworkManager.shared.getComments(cardId: cardID, page: page, perPage: perPage) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    completion(response.success ? .page(response.data, total: response.total) : .failed)
                case .failure(let error):
                    completion(error.invalidatesCardRead ? .accessLost : .failed)
                }
            }
        }
    }
}
