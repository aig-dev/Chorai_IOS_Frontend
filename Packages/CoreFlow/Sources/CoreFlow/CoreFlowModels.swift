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
    public let contentJSON: String?
    public let backgroundMediaRef: String?
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
    public let isOwner: Bool

    public init(
        id: String,
        title: String?,
        content: String,
        contentJSON: String? = nil,
        backgroundMediaRef: String? = nil,
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
        author: FlowAuthor?,
        isOwner: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.contentJSON = contentJSON
        self.backgroundMediaRef = backgroundMediaRef
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
        self.isOwner = isOwner
    }

    func applyingOwnedAction(_ commit: OwnedCardActionCommit) -> FlowCard {
        guard id == commit.cardID, isOwner else { return self }
        var updatedPublic = isPublic
        var updatedPinned = isPinned
        var updatedPinnedAt = pinnedAt
        switch commit {
        case .visibility(_, let isPublic): updatedPublic = isPublic
        case .pin(_, let isPinned, let pinnedAt):
            updatedPinned = isPinned
            updatedPinnedAt = pinnedAt
        case .removed: return self
        }
        return FlowCard(
            id: id, title: title, content: content, contentJSON: contentJSON,
            backgroundMediaRef: backgroundMediaRef, contentHash: contentHash,
            tags: tags, isPublic: updatedPublic, createdAt: createdAt, updatedAt: updatedAt,
            favoriteCount: favoriteCount, likeCount: likeCount, commentCount: commentCount,
            rate: rate, isFavorited: isFavorited, isLiked: isLiked,
            isPinned: updatedPinned, pinnedAt: updatedPinnedAt, author: author, isOwner: isOwner
        )
    }

    public func replacingLike(with state: CardLikeState) -> FlowCard {
        FlowCard(
            id: id,
            title: title,
            content: content,
            contentJSON: contentJSON,
            backgroundMediaRef: backgroundMediaRef,
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
            author: author,
            isOwner: isOwner
        )
    }

    public func replacingFavorite(
        isFavorited: Bool,
        favoriteCount: Int
    ) -> FlowCard {
        FlowCard(
            id: id,
            title: title,
            content: content,
            contentJSON: contentJSON,
            backgroundMediaRef: backgroundMediaRef,
            contentHash: contentHash,
            tags: tags,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt,
            favoriteCount: favoriteCount,
            likeCount: likeCount,
            commentCount: commentCount,
            rate: rate,
            isFavorited: isFavorited,
            isLiked: isLiked,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            author: author,
            isOwner: isOwner
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

public enum CoreTab: Int, CaseIterable, Sendable {
    case flow
    case library
    case chat
}

public enum FlowSwipeDecision: Equatable, Sendable {
    case advanceLeft
    case advanceRight
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
            return translation > 0 ? .advanceRight : .advanceLeft
        }

        guard abs(predictedEndTranslation) >= predictionThreshold else {
            return .cancel
        }

        return predictedEndTranslation > 0 ? .advanceRight : .advanceLeft
    }
}

/// A committed favorite state shared between detail, library, and Explore.
/// Missing counts are allowed when an endpoint returns only the action result.
public struct CardFavoriteState: Equatable, Sendable {
    public let cardID: String
    public let isFavorited: Bool
    public let favoriteCount: Int?

    public init(cardID: String, isFavorited: Bool, favoriteCount: Int?) {
        self.cardID = cardID
        self.isFavorited = isFavorited
        self.favoriteCount = favoriteCount
    }
}
