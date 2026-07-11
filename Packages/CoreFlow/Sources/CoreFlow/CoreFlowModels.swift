import Foundation

public struct FlowAuthor: Equatable, Sendable {
    public let id: String
    public let username: String
    public let avatarURL: String?

    public init(id: String, username: String, avatarURL: String?) {
        self.id = id
        self.username = username
        self.avatarURL = avatarURL
    }
}

public struct FlowCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let content: String
    public let contentHash: String?
    public let tags: [String]
    public let isPublic: Bool
    public let createdAt: String
    public let updatedAt: String
    public let favoriteCount: Int
    public let likeCount: Int
    public let commentCount: Int
    public let rate: Int
    public let isFavorited: Bool
    public let isLiked: Bool
    public let isPinned: Bool
    public let pinnedAt: String?
    public let author: FlowAuthor?

    public init(
        id: String,
        title: String?,
        content: String,
        contentHash: String?,
        tags: [String],
        isPublic: Bool,
        createdAt: String,
        updatedAt: String,
        favoriteCount: Int,
        likeCount: Int,
        commentCount: Int,
        rate: Int,
        isFavorited: Bool,
        isLiked: Bool,
        isPinned: Bool,
        pinnedAt: String?,
        author: FlowAuthor?
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.contentHash = contentHash
        self.tags = tags
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.favoriteCount = favoriteCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.rate = rate
        self.isFavorited = isFavorited
        self.isLiked = isLiked
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.author = author
    }

    public func replacingLike(with state: CardLikeState) -> FlowCard {
        FlowCard(
            id: id,
            title: title,
            content: content,
            contentHash: contentHash,
            tags: tags,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt,
            favoriteCount: favoriteCount,
            likeCount: state.likeCount,
            commentCount: commentCount,
            rate: rate,
            isFavorited: isFavorited,
            isLiked: state.isLiked,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            author: author
        )
    }
}

public struct FlowPage: Equatable, Sendable {
    public let cards: [FlowCard]
    public let nextRefreshToken: String?

    public init(cards: [FlowCard], nextRefreshToken: String?) {
        self.cards = cards
        self.nextRefreshToken = nextRefreshToken
    }
}

public struct CreatedCard: Equatable, Sendable {
    public let id: String
    public let content: String
    public let isPublic: Bool

    public init(id: String, content: String, isPublic: Bool) {
        self.id = id
        self.content = content
        self.isPublic = isPublic
    }
}

public enum CoreFlowError: Error, Equatable, Sendable {
    case unauthorized
    case offline
    case timeout
    case decoding
    case server
    case unknown
}

public enum FlowDeckPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum FlowNotice: Equatable, Sendable {
    case saved(assetID: String)
    case saveFailed
    case undoFailed
}

public enum CapturePhase: Equatable, Sendable {
    case idle
    case saving
    case failed(String)
}

public enum CoreTab: Int, CaseIterable, Sendable {
    case flow
    case library
    case chat
}

public enum FlowSwipeDecision: Equatable, Sendable {
    case dismiss
    case save
    case cancel
}

public enum FlowSwipeResolver {
    public static func resolve(
        translation: Double,
        predictedEndTranslation: Double,
        translationThreshold: Double = 88,
        predictionThreshold: Double = 132
    ) -> FlowSwipeDecision {
        if abs(translation) >= translationThreshold {
            return translation > 0 ? .save : .dismiss
        }

        guard abs(predictedEndTranslation) >= predictionThreshold else {
            return .cancel
        }

        return predictedEndTranslation > 0 ? .save : .dismiss
    }
}
