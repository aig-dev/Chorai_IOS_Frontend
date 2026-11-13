import Foundation

public struct CardLikeState: Equatable, Sendable {
    public let cardID: String
    public let isLiked: Bool
    public let likeCount: Int

    public init(cardID: String, isLiked: Bool, likeCount: Int) {
        self.cardID = cardID
        self.isLiked = isLiked
        self.likeCount = max(0, likeCount)
    }

    func settingLiked(_ liked: Bool) -> CardLikeState {
        guard liked != isLiked else { return self }
        return CardLikeState(cardID: cardID, isLiked: liked, likeCount: likeCount + (liked ? 1 : -1))
    }
}

public enum CardLikeError: Error, Equatable, Sendable {
    case transport(code: String)
}

public enum CardLikePhase: Equatable, Sendable {
    case ready
    case mutating(targetLiked: Bool)
    case failed(CardLikeError)
}
