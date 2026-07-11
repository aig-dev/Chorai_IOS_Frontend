import Foundation

public protocol CoreCardLikeServing: Sendable {
    func setLiked(cardID: String, liked: Bool) async throws
}
