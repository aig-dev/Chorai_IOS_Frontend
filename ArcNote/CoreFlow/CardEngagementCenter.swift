import Combine
import CoreFlow
import Foundation

@MainActor
final class CardEngagementCenter {
    static let shared = CardEngagementCenter()

    let likes = PassthroughSubject<CardLikeState, Never>()

    private init() {}

    func publish(_ state: CardLikeState) {
        likes.send(state)
    }
}
